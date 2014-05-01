package Dist::Zilla::Plugin::Travis::TestRelease;

# VERSION
# ABSTRACT: makes sure repo passes Travis tests before release

#############################################################################
# Modules

use Moose;
use sanity;

use Try::Tiny;
use List::AllUtils qw( first sum );
use Net::Travis::API::UA;
use Date::Parse 'str2time';
use Date::Format 'time2str';
use Storable 'dclone';
use File::pushd ();
use File::Copy ();

use Dist::Zilla::Util::Git::Bundle;

with 'Dist::Zilla::Role::BeforeRelease';

#############################################################################
# Private Attributes

has _git_bundle => (
   is       => 'ro',
   isa      => 'Dist::Zilla::Util::Git::Bundle',
   lazy     => 1,
   init_arg => undef,
   handles  => { _git => 'git' },
   default  => sub {
      my $self = shift;
      Dist::Zilla::Util::Git::Bundle->new(
         ### XXX: deep recursion on the branches
         zilla         => $self->zilla,
         #branch        => $self->branch,
         remote_name   => $self->remote,
         #remote_branch => $self->remote_branch,
      );
   },
);
has _travis_ua => (
   is       => 'ro',
   isa      => 'Net::Travis::API::UA',
   lazy     => 1,
   init_arg => undef,
   default  => sub {
      my $ua = Net::Travis::API::UA->new;
      $ua->agent(__PACKAGE__."/$VERSION ");  # prepend our own UA string
      return $ua;
   }
);

#############################################################################
# Public Attributes

has branch => (
   is      => 'ro',
   lazy    => 1,
   default => sub { join('/', 'release_testing', shift->_git_bundle->current_branch) },
);
has remote_branch => (
   is      => 'ro',
   lazy    => 1,
   default => sub { shift->branch },
);
has remote => (
   is      => 'ro',
   default => 'origin',
);
has slug => (
   is      => 'ro',
   lazy    => 1,
   default => sub {
      my $self = shift;
      my @github = $self->_git_bundle->acquire_github_repo_info;
      $self->log_fatal(["Remote '%s' is not a Github repo!", $self->remote]) unless @github;

      return join('/', @github);
   },
);
has create_builddir => (
   is      => 'ro',
   isa     => 'Bool',
   default => 0,
);

#############################################################################
# Methods

my %RESULT_MAP = (
   '' => 'Error',
   0  => 'Pass',
   1  => 'Fail',
);

sub before_release {
   my ($self, $tgz) = @_;

   my $gb   = $self->_git_bundle;
   my $git  = $self->_git;

   $gb->branch($self->branch);
   $gb->_remote_branch($self->remote_branch);

   # FETCH ALL THE BRANCHES!!!
   my @local_branches = $git->branch;
   my $current_branch = $gb->current_branch;
   my $testing_branch = $self->branch;

   $self->log_fatal('Must be in a branch!') unless $current_branch;
   $self->log_fatal('Must not be in the testing branch!') if ($current_branch eq $testing_branch);

   my $slug = $self->slug;

   ### Local setup

   ### TODO: Replace all of these log_debugs with an overloaded Git::Wrapper object

   # Get the last refhash, as we'll need it for our "hard stash pop"
   my ($refhash) = $git->rev_parse({ verify => 1 }, 'HEAD');

   # Stash any leftover files
   $self->log("Stashing any files and switching to '$testing_branch' branch...");
   my $has_changed_files = scalar (
      $git->diff({ cached => 1, name_status => 1 }),
      $git->ls_files({
         modified => 1,
         deleted  => 1,
         others   => 1,
      }),
   );
   if ($has_changed_files) {
      $self->log_debug($_) for $git->stash(save => {
         # save everything, including untracked and ignored files
         include_untracked => 1,
         all               => 1,
      }, "Stash of changed/untracked files for Travis release testing");
   }

   # Entering a try/catch, so that we can back out any git changes before we die
   my $prev_repo_info;
   try {
      # Sync up the release_testing branch with the main branch
      if ($gb->is_local_branch_new) {
         $self->log_debug($_) for $git->checkout({ b => 1 }, $testing_branch, $current_branch);
      }
      else {
         $self->log_debug($_) for $git->checkout($testing_branch);
         $self->log_debug($_) for $git->reset({ hard => 1 }, $current_branch);
      }

      if ($has_changed_files) {
         $self->log_debug($_) for $git->stash('apply');
         $self->log_debug($_) for $git->add({ all => 1 }, '.');
      }

      # Add in the build directory, if requested
      if ($self->create_builddir) {
         my $build_dir = $self->zilla->root->subdir('.build');
         $build_dir->mkpath unless -d $build_dir;

         $self->log("Extracting $tgz to ".$build_dir->subdir('testing')->stringify);

         require Archive::Tar;

         $tgz = $tgz->absolute;
         my @files = do {
            my $wd = File::pushd::pushd($build_dir);
            Archive::Tar->extract_archive("$tgz");
            File::Copy::move( $self->zilla->dist_basename, 'testing' );
         };

         $self->log_fatal([ "Failed to extract archive: %s", Archive::Tar->error ]) unless @files;

         $self->log_debug($_) for $git->add({
            all   => 1,
            force => 1,  # this is probably already on the .gitignore list
         }, $build_dir->relative->stringify);
      }

      $self->log_debug($_) for $git->commit({
         all         => 1,
         allow_empty => 1,  # because it might be ran multiple times without changes
         message     => "Travis release testing for local branch $current_branch",
      });

      # final check
      $gb->check_local;
      $self->log("Local branch cleanup complete!");

      # Check TravisCI prior to the push to make sure the distro works and exists
      $self->log('Checking Travis CI...');
      $prev_repo_info = $self->travisci_api_get_repo;

      ### Remote setup

      # Verify the branch is up to date
      $git->remote('update', $gb->remote) unless $gb->is_remote_branch_new;

      # Push it to the remote
      # (force because we are probably overwriting history of release_testing branch)
      $self->log_debug($_) for $git->push({ force => 1 }, $gb->remote, 'HEAD:'.$testing_branch);
      $self->log('Pushed to remote repo!');

      $self->log("Switching back to '$current_branch' branch...");
      $self->log_debug($_) for $git->checkout($current_branch);

      ### XXX: Okay, so "git stash pop" just won't work when the files already exist.  However, we just stashed this thing and we
      ### know it was copied from the current branch.  A stash is the same as the branch except with a few extra commits.

      ### Let's force the branch to the stash itself, and then walk the index back a few steps.

      if ($has_changed_files) {
         $self->log_debug($_) for $git->reset({ hard => 1 }, 'stash@{0}');
         $self->log_debug($_) for $git->reset($refhash);
         $self->log_debug($_) for $git->stash('drop', 'stash@{0}');
      }
   }
   catch {
      # make sure nothing is dangling, get back to the old checkout, and reverse the stash
      my $error = $_;

      $self->log('Caught an error; backing out...');
      $self->log_debug($_) for $git->reset({ hard => 1 });
      $self->log_debug($_) for $git->checkout($current_branch);
      if ($has_changed_files) {
         $self->log_debug($_) for $git->reset({ hard => 1 }, 'stash@{0}');
         $self->log_debug($_) for $git->reset($refhash);
         $self->log_debug($_) for $git->stash('drop', 'stash@{0}');
      }
      $self->log('Backout complete!');

      die $error;
   };

   # Start a clock
   my $start_time = time;
   $self->_set_time_prefix($start_time);
   $self->log('Checking Travis CI for test details...');

   # Run through the API polling loop
   my $repo_info;
   while (1) {
      $repo_info = $self->travisci_api_get_repo;
      $self->_set_time_prefix($start_time);

      if (
         $repo_info->{last_build_number} >  $prev_repo_info->{last_build_number} ||
         $repo_info->{last_build_id}     != $prev_repo_info->{last_build_id}
      ) {
         my $build_time = str2time($repo_info->{last_build_started_at}, 'GMT');
         $self->log([ 'Build %u started at %s', $repo_info->{last_build_number}, time2str('%l:%M%p', $build_time) ]);
         $self->log([ 'Status URL: https://travis-ci.org/%s/builds/%u', $self->slug, $repo_info->{last_build_id} ]);
         last;
      }

      $self->log_fatal("Waited over 5 minutes and TravisCI still hasn't even seen the new commit yet!") if (time - $start_time > 5*60);
      sleep 10;
   };

   $self->_set_time_prefix($start_time);

   # Get a relative idea of test duration for polling time
   my $last_test_duration =
      str2time($prev_repo_info->{last_build_finished_at}, 'GMT') -
      str2time($prev_repo_info->{last_build_started_at},  'GMT')
   ;
   my $poll_freq = int($last_test_duration / 4);
   $poll_freq = 10  if $poll_freq < 10;
   $poll_freq = 120 if $poll_freq > 120;

   # Another polling loop with the build status
   my $prev_build_info;
   $start_time = time;
   while (1) {
      my $build_info = $self->travisci_api_get_build($repo_info->{last_build_id});
      $self->_set_time_prefix($start_time);

      # aggregiate job details
      my @matrix   = @{ $build_info->{matrix} };
      my @started  = grep { defined $_->{started_at}  } @matrix;
      my @finished = grep { defined $_->{finished_at} } @matrix;

      my $total_jobs = int @matrix;
      my $pending    = int @matrix  - @started;
      my $running    = int @started - @finished;
      my $finished   = int @finished;
      my $passed     = int scalar grep { $RESULT_MAP{ $_->{result} } eq 'Pass' } @finished;
      my $allow_fail = int scalar grep { $RESULT_MAP{ $_->{result} } ne 'Pass' &&  $_->{allow_failure} } @finished;
      my $failed     = int scalar grep { $RESULT_MAP{ $_->{result} } ne 'Pass' && !$_->{allow_failure} } @finished;

      my @job_status;
      push @job_status, sprintf('%u jobs pending', $pending) if $pending;
      push @job_status, sprintf('%u jobs running', $running) if $running;

      if ($finished) {
         push @job_status, sprintf('%u jobs finished', $finished);
         push @job_status,
            $allow_fail ?
               sprintf('%u/%u/%u jobs passed/failed/allowed to fail', $passed, $failed, $allow_fail) :
               sprintf('%u/%u jobs passed/failed', $passed, $failed)
         ;
      }

      # fake a $prev_build_info if it doesn't exist
      unless ($prev_build_info) {
         $prev_build_info = dclone $build_info;
         foreach my $job (@{ $prev_build_info->{matrix} }) {
            $job->{started_at}  = undef;
            $job->{finished_at} = undef;
            $job->{result}      = undef;
         }
      }

      # individual job updates
      my %prev_matrix = map { $_->{number} => $_ } @{ $prev_build_info->{matrix} };

      foreach my $job (@matrix) {
         my $prev = $prev_matrix{ $job->{number} };

         # jobs that have started
         if (!defined $prev->{started_at} && defined $job->{started_at}) {
            my $config = $job->{config};
            my @config_label;
            push @config_label, 'Perl '.$config->{perl} if $config->{perl};
            push @config_label, $config->{env} if $config->{env};

            $self->log(['   Job %s%s started at %s',
               $job->{number},
               (@config_label ? ' ('.join(', ', @config_label).')' : ''),
               time2str('%l:%M%p', str2time($job->{started_at}, 'GMT') ),
            ]);
         }

         # jobs that have finished
         if    (!defined $prev->{finished_at} && defined $job->{finished_at}) {
            my $result = $RESULT_MAP{ $job->{result} };
            $result .= ' (allowed)' if ($result eq 'Fail' && $job->{allow_failure});

            my $finish_time = str2time($job->{finished_at}, 'GMT');

            $self->log(['   Job %s finished at %s with a status of %s', $job->{number}, time2str('%l:%M%p', $finish_time), $result ]);
         }
      }
      $prev_build_info = $build_info;

      $self->log('   === '.join(', ', @job_status));

      ### NOTE: Travis' Fast Finish feature will already speed up the build status, so just honor that feature and don't use
      ### $failed to determine if the build is finished.

      # figure out if we need to exit or not
      if ($build_info->{state} eq 'finished') {
         my $result = $RESULT_MAP{ $build_info->{result} };

         my $finish_time = str2time($build_info->{finished_at}, 'GMT');

         $self->log([ 'Build %u finished at %s with a status of %s', $build_info->{number}, time2str('%l:%M%p', $finish_time), $result ]);
         $self->logger->set_prefix('');

         $self->log_fatal("Travis CI build didn't pass!") unless $result eq 'Pass';
         last;
      }

      $self->log_fatal("Waited over an hour and the build still hasn't finished yet!") if (time - $start_time > 60*60);

      $poll_freq = int($poll_freq / 2) if ($finished and not $pending || time - $start_time >= $last_test_duration * 0.75);
      $poll_freq = 10 if $poll_freq < 10;
      sleep $poll_freq;
   };

   return 1;
}

sub travisci_api_get_repo {
   my ($self) = @_;

   my $result = $self->_travis_ua->get('/repos/'.$self->slug);
   $self->log_fatal("Travis CI API reported back with: $result") unless $result->content_type eq 'application/json';

   my $repo_info = $result->content_json;
   $self->log_fatal("Travis CI cannot find your repository; did you forget to configure it?") if $repo_info->{file} eq 'not found';

   return $repo_info;
}

sub travisci_api_get_build {
   my ($self, $build_id) = @_;

   my $result = $self->_travis_ua->get('/repos/'.$self->slug."/builds/$build_id");
   $self->log_fatal("Travis CI API reported back with: $result") unless $result->content_type eq 'application/json';

   my $build_info = $result->content_json;
   $self->log_fatal("Travis CI cannot find your build?!?") if $build_info->{file} eq 'not found';

   return $build_info;
}

sub _set_time_prefix {
   my ($self, $start_time) = @_;
   my $time_diff = time - $start_time;
   my $min = int($time_diff / 60);
   my $sec = $time_diff % 60;

   $self->logger->set_prefix( sprintf('(%02u:%02u) ', $min, $sec) );
}

__PACKAGE__->meta->make_immutable;
42;

__END__

=begin wikidoc

= SYNOPSIS

   ;;; Test DZIL

   [Travis::TestRelease]
   ; defaults typically work fine

   ;;; Test DZIL+build

   [TravisYML]
   support_builddir = 1
   ; (optional) only test with Travis::TestRelease
   dzil_branch = /^release_testing\/.*/

   [Travis::TestRelease]
   create_builddir = 1

= DESCRIPTION

Tired of releasing a module only to discover that it failed Travis tests?  This plugin solves that problem.

It pushes a release testing branch to Travis, monitors the testing, and aborts the release if the Travis build fails.  It also
supports testing the non-DZIL build directory directly.

[TravisYML|Dist::Zilla::Plugin::TravisYML] is not required to use this plugin, even for build testing, but is still recommended.

= DETAILS

Starting the process requires creating and pushing a release testing branch to GitHub.  This is done through a series of git
commands, designed to work with the dirtiest of branch states:

0 If there are any "dirty files", even untracked files, put them into a git stash.
0 Create or hard reset the release testing branch to match the main branch.
0 Apply the stash (if created) and add any new files.
0 If a build directory is requested, extract it into .build/testing, and add it.
0 Commit the changes.
0 Force push the testing branch to the repo.
0 Switch back to the main branch.
0 If any files were stashed, apply it back to the branch.  This is done by hard resetting the main branch to the stash (don't panic;
it's just a copy of the branch with a few extra commits), and then walking the index back to the refhash it was at originally.

As you may notice, the testing branch is subject to harsh and overwriting changes, so *don't rely on the branch for anything except
release testing!*

After the branch is pushed, the plugin checks Travis (via API) to make sure it starts testing.  Monitoring stops when Travis says
the build is finished.  Use of [Travis' Fast Finish option|http://docs.travis-ci.com/user/build-configuration/#Fast-finishing] is
recommended to speed up test results.

= OPTIONS

== remote

Name of the remote repo.

The default is {origin}.

== branch

Name of the local release testing branch.  *Do not use this branch for anything except release testing!*

The default is {release_testing/$current_branch}.

== remote_branch

Name of the remote branch.

The default is whatever the {branch} option is set to.

== slug

Name of the "slug", or username/repo combo, that will be used to query the test details.  For example, this distro has a slug of
{SineSwiper/Dist-Zilla-TravisCI}.

The default is auto-detection of the slug using the remote URL.

== create_builddir

Boolean; determines whether to create a build directory or not.  If turned on, the plugin will create a {.build/testing}
directory in the testing branch to be used for build testing.  Whether this is actually used depends on the {.travis.yml} file.
For example, [TravisYML|Dist::Zilla::Plugin::TravisYML]'s {support_builddir} switch will create a Travis matrix in the YAML file
to test both DZIL and build directories on the same git branch.  If you're not using that plugin, you should at least implement
something similar to make use of dual DZIL+build tests.

Default is off.

= CAVEATS

Plugin order is important.  Since Travis build testing takes several minutes, this should be one of the last {before_release}
plugins in your dist.ini, after plugins like [TestRelease|Dist::Zilla::Plugin::TestRelease], but still just before
[ConfirmRelease|Dist::Zilla::Plugin::ConfirmRelease].

The amount of git magic and little used switches required to make and push the branch to GitHub may be considered questionable by
some, especially force pushes and hard resets.  But it is all required to make sure testing occurs from any sort of branch state.
And it works.

Furthermore, it's not the job of this plugin to make sure the branch state is clean.  Use plugins like
[Git::Check|Dist::Zilla::Plugin::Git::Check] for that.
