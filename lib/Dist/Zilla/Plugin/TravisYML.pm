package Dist::Zilla::Plugin::TravisYML;

our $VERSION = '0.98_02'; # VERSION
# ABSTRACT: creates a .travis.yml file for Travis CI

use sanity;

use Moose;

use Dist::Zilla::File::InMemory;
use List::AllUtils 'first';

# DZIL role ordering gets really weird here...

# FilePruner   - Since the .travis.yml file doesn't belong in the build
# InstallTool  - Both cases need to be here after prereqs are built
# AfterRelease - So that we have the build version in the build directory for Git::CommitBuild

with 'Dist::Zilla::Role::FilePruner';
with 'Dist::Zilla::Role::InstallTool';
with 'Dist::Zilla::Role::AfterRelease';

with 'Dist::Zilla::Role::FileInjector';
with 'Dist::Zilla::Role::TravisYML';

around mvp_multivalue_args => sub {
   my ($orig, $self) = @_;
   
   my @start = $self->$orig;
   return (
      @start, qw(notify_email notify_irc irc_template extra_env),
      ### XXX: Yes, this ends up being 7*3*3=63 attributes, but such is the price of progress...
      (
         map { $_, $_.'_dzil', $_.'_build' }
         map { $_, 'pre_'.$_, 'post_'.$_ }
         @Dist::Zilla::Role::TravisYML::phases
      ),
   );
};

sub prune_files {
   my ($self, $opt) = @_;
   my $file = first { $_->name eq '.travis.yml' } @{$self->zilla->files};

   ### !!! NINJA !!! ###
   $self->zilla->prune_file($file) if $file;
}

# Not much here... most of the magic is in the role
sub setup_installer {
   my $self = shift;
   $self->build_travis_yml;
}

sub after_release {
   my $self = shift;
   return unless $self->build_branch;
   my $file = $self->build_travis_yml(1) || return;
   
   # Now we have to add the file back in
   $self->add_file(
      # Since we put the file in the build directory, we have to use InMemory to
      # prevent the file paths from getting mismatched with what is in zilla->files
      Dist::Zilla::File::InMemory->new({
         name    => '.travis.yml',
         content => $file->slurp,
         mode    => $file->stat->mode & 0755, # kill world-writeability
      })
   );
}

__PACKAGE__->meta->make_immutable;
42;

__END__

=pod

=encoding utf-8

=head1 NAME

Dist::Zilla::Plugin::TravisYML - creates a .travis.yml file for Travis CI

=head1 SYNOPSIS

    [TravisYML]
    ; defaults
    build_branch = /^build\/.*/
    notify_email = 1
    notify_irc   = 0
    mvdt         = 0
 
    ; These options are probably a good idea
    ; if you are going to use a build_branch
    [Git::CommitBuild]
    release_branch  = build/%b
    release_message = Release build of v%v (on %b)
 
    [@Git]
    allow_dirty = dist.ini
    allow_dirty = README
    allow_dirty = .travis.yml
    push_to = origin master:master
    push_to = origin build/master:build/master

=head1 DESCRIPTION

This plugin creates a C<<< .travis.yml >>> file in your distro for CI smoke testing (or what we like
to call L<"chain smoking"|Dist::Zilla::App::Command::chainsmoke/CHAIN SMOKING?>).  It will also
(optionally) create a separate C<<< .travis.yml >>> file for your build directory after a release.

Why two files?  Because chain smoking via DZIL will work a lot differently than a traditional 
C<<< Makefile.PL; make >>>.  This tests both your distribution repo environment as well as what a 
CPAN user would see.

Of course, you still need to turn on TravisCI and the remote still needs to be a GitHub repo
for any of this to work.

=head1 OPTIONS

=head2 build_branch

This is a regular expression indicating which (build) branches are okay for running through
Travis CI, per the L<configuration|http://about.travis-ci.org/docs/user/build-configuration/>'s
branch whitelist option.  The value will be inserted directly as an C<<< only >>> clause.  The default
is C<<< /^build\/.*/ >>>.

This more or less requires L<Git::CommitBuild|Dist::Zilla::Plugin::Git::CommitBuild> to work.  
(Ordering is important, too.  TravisYML comes before Git::CommitBuild.)  You should change
this to match up with the C<<< release_branch >>> option, if your build branch is not going to reside
in a C<<< build/* >>> structure.

Also, if you want to disable build branch testing, you can set this to C<<< 0 >>>.

=head2 notify_email

This affects the notification options of the resulting YML file.  It can either be set to:

=over

=item *

C<<< 0 >>> = Disable email notification

=item *

C<<< 1 >>> = Enable email notification, using Travis CI's default email scheme

=item *

C<<< foo@bar.com >>> (can be multiple; one per line) = Enable email notification to these email
addresses

=back

The default is C<<< 1 >>>.

=head2 notify_irc

This affects the notification options of the resulting YML file.  It can either be set to:

=over

=item *

C<<< 0 >>> = Disable IRC notification

=item *

C<<< 1 >>> = Enable IRC notification, using the C<<< IRC >>> or C<<< x_irc >>> meta resource value

=item *

C<<< irc://irc.perl.org/#roomname >>> (can be multiple; one per line) = Enable IRC notification
to these IRC serverE<sol>rooms

=back

The default is C<<< 0 >>>.  Please ask permission from the room channel operators before enabling
bot notification.

=head2 irc_template

Only applies when IRC notification is on.  The default is:

    %{branch}#%{build_number} by %{author}: %{message} (%{build_url})

This option can be specified more than once for multiple lines.  See L<Travis-CI's IRC notification docs|http://about.travis-ci.org/docs/user/notifications/#IRC-notification>
for a list of variables that can be used.

=head2 perl_version

This is a space-delimited option with a list of the perl versions to test against.  The default
is all supported versions available within Travis.  You can restrict it down to only a few like
this:

    perl_version = 5.10 5.12

Note that any custom settings here will prevent any newer versions from being auto-added (as this
distro is updated).

=head2 mvdt

Turning this on enables L<Minimum Version Dependency Testing|Dist::Zilla::TravisCI::MVDT>.  This
will make your YML file less of a static file, as it will now include commands to forcefully
B<downgrade> your dependencies to the lowest version that your prereqs said they would be able
to use.

While going through the MVDT process is recommended, it can be a royal pain-in-the-ass
sometimes, so this option isn't on by default.  It's HIGHLY recommended that you read the above
doc first to get an idea of what you're diving into.

This applies to both YML files.

=head2 test_authordeps

Controls whether author dependencies will be tested while DZIL chainsmoking.  This option
is also directly linked to verbosity and parallelization of the author deps:

=over

=item *

C<<< 0 >>> = No tests or verbosity, all files are downloadedE<sol>installed in parallel (10 processes at a time)

=item *

C<<< 1 >>> = Each module is downloaded one at a time, tested, and with verbosity turned on

=back

The default is C<<< 0 >>>.

=head2 test_deps

Just like C<<< test_authordeps >>>, but for the real deps that the module needs.  This also affects
testing for build chainsmoking as well.

The default is C<<< 1 >>>.

=head2 Custom Commands

For the most part, the default command sets for TravisYML serves its purpose.  However, you may
have some unusual situation from within your distro that demands a custom command or two.  For
that purpose, there is a set of "dynamic" options available to add or replace any part of the
command list for Travis.

They are in the form of:

    $pos$phase$filetype
 
    $pos      = Either 'pre_' or 'post_' (optional)
    $phase    = One of the Travis-CI testing phases (required)
    $filetype = Either '_dzil' or '_build' (optional)

See L<Travis-CI's Build Lifecycle|http://about.travis-ci.org/docs/user/build-configuration/#Build-Lifecycle>
for a list of phases.

The positions determine if the commands are to be added at the beginning (C<<< pre_ >>>), the end (C<<< post_ >>>), or
replacing (no prefix) the existing code.  Replace entire blocks at your own risk; TravisYML may change
the blocks for bug fixes or new features.

The file type determines if these command changes are for the DZIL YML file (C<<< _dzil >>>), the build YML file
(C<<< _build >>>), or both (no suffix).

For example, this would give you the following combinations for the 'before_install' phase:

    before_install            = Replace all before_install blocks
    pre_before_install        = Unshift lines to all before_install blocks
    post_before_install       = Push lines to all before_install blocks
    before_install_dzil       = Replace DZIL before_install block
    pre_before_install_dzil   = Unshift lines to DZIL before_install block
    post_before_install_dzil  = Push lines to DZIL before_install block
    before_install_build      = Replace build before_install block
    pre_before_install_build  = Unshift lines to build before_install block
    post_before_install_build = Push lines to build before_install block

These options are all multi-lined, so you can add as many commands as you need:

    pre_install_dzil = export AUTHOR_TESTING=1
    pre_install_dzil = echo "Author testing is now "$AUTHOR_TESTING

=head1 AVAILABILITY

The project homepage is L<https://github.com/SineSwiper/Dist-Zilla-TravisCI/wiki>.

The latest version of this module is available from the Comprehensive Perl
Archive Network (CPAN). Visit L<http://www.perl.com/CPAN/> to find a CPAN
site near you, or see L<https://metacpan.org/module/Dist::Zilla::TravisCI/>.

=head1 AUTHOR

Brendan Byrd <bbyrd@cpan.org>

=head1 CONTRIBUTORS

=over 4

=item *

Graham Knop <haarg@haarg.org>

=item *

Torsten Raudssus <torsten@raudss.us>

=back

=head1 COPYRIGHT AND LICENSE

This software is Copyright (c) 2013 by Brendan Byrd.

This is free software, licensed under:

  The Artistic License 2.0 (GPL Compatible)

=cut
