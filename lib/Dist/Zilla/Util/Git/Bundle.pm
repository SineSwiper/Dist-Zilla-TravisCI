package Dist::Zilla::Util::Git::Bundle;

# VERSION
# ABSTRACT: Helper class with misc git methods

use sanity;

use Moose;

use List::AllUtils 'first';
use Dist::Zilla::Util::Git::Wrapper;

has zilla => (
   isa      => 'Dist::Zilla',
   is       => 'ro',
   required => 1,
);

has logger => (
   is      => 'ro',
   lazy    => 1,
   handles => [ qw(log log_debug log_fatal) ],
   default => sub { shift->zilla->logger },
);

has branch => (
   isa     => 'Str',
   is      => 'rw',
   lazy    => 1,
   default => sub { shift->current_branch },
);

has _git_wrapper_util => (
   isa     => 'Dist::Zilla::Util::Git::Wrapper',
   is      => 'ro',
   lazy    => 1,
   handles => [ qw(git) ],
   default => sub { Dist::Zilla::Util::Git::Wrapper->new( zilla => shift->zilla ); },
);

### HACK: Needed for DirtyFiles, though this is really only used for Plugins ###
sub mvp_multivalue_args { }
### HACK: Ditto for ...::Git::Repo (expects 'Dist::Zilla::Role::ConfigDumper').
sub dump_config { return {} }

with 'Dist::Zilla::Role::Git::Repo';
with 'Dist::Zilla::Role::Git::DirtyFiles';
sub _build_allow_dirty { [ ] }  # overload

with 'Dist::Zilla::Role::Git::Remote';
with 'Dist::Zilla::Role::Git::Remote::Branch';
with 'Dist::Zilla::Role::Git::Remote::Check';

has '+_remote_branch' => ( lazy => 1, default => sub { shift->branch } );

sub current_branch {
   my ($branch) = shift->git->symbolic_ref({ quiet => 1 }, 'HEAD');
   $branch =~ s|^refs/heads/||;
   return $branch;
}

### LAZY: This is pretty much a straight copy of Dist::Zilla::Plugin::Git::Check. ###
sub check_local {
   my $self = shift;
   my $git = $self->git;
   my @output;

   # fetch current branch
   my $branch = $self->current_branch;

   # check if some changes are staged for commit
   @output = $git->diff( { cached=>1, 'name-status'=>1 } );
   if ( @output ) {
      my $errmsg =
         "branch $branch has some changes staged for commit:\n" .
         join "\n", map { "\t$_" } @output;
      $self->log_fatal($errmsg);
   }

   # everything but files listed in allow_dirty should be in a
   # clean state
   @output = $self->list_dirty_files($git);
   if ( @output ) {
      my $errmsg =
         "branch $branch has some uncommitted files:\n" .
         join "\n", map { "\t$_" } @output;
      $self->log_fatal($errmsg);
   }

   # no files should be untracked
   @output = $git->ls_files( { others=>1, 'exclude-standard'=>1 } );
   if ( @output ) {
      my $errmsg =
         "branch $branch has some untracked files:\n" .
         join "\n", map { "\t$_" } @output;
      $self->log_fatal($errmsg);
   }
}

sub is_local_branch_new {
   my ($self, $lb) = @_;
   my $git  = $self->git;
   $lb //= $self->branch;
   return ( first { s/^\*?\s+//; $_ eq $lb } $git->branch ) ? 0 : 1;
}

sub is_remote_branch_new {
   my ($self, $rb) = @_;
   my $git  = $self->git;
   $rb //= $self->remote_branch;
   return ( first { /^\s*\Q$rb\E\s*$/ } $git->branch({ remotes => 1 }) ) ? 0 : 1;
}

# Stolen and warped from Dist::Zilla::Plugin::GithubMeta
sub acquire_github_repo_info {
   my $self = shift;

   my $git_url;
   my $remote = $self->remote;

   # Missing remotes expand to the same value as they were input
   unless ($git_url = $self->url_for_remote($remote) and $remote ne $git_url) {
      $self->log(["A remote named '%s' was specified, but does not appear to exist.", $remote]);
      return;
   }

   # Not a Github Repository?
   unless ($git_url =~ m!\bgithub\.com[:/]!) {
      $self->log([
         'Specified remote \'%s\' expanded to \'%s\', which is not a github repository URL',
         $remote, $git_url,
      ]);
      return;
   }

   my ($user, $repo) = $git_url =~ m{
      github\.com              # the domain
      [:/] ([^/]+)             # the username (: for ssh, / for http)
      /    ([^/]+?) (?:\.git)? # the repo name
      $
   }ix;

   $self->log(['No user could be discerned from URL: \'%s\'',       $git_url]) unless defined $user;
   $self->log(['No repository could be discerned from URL: \'%s\'', $git_url]) unless defined $repo;
   return unless defined $user and defined $repo;

   return ($user, $repo);
}

sub url_for_remote {
   my ($self, $remote) = @_;
   foreach my $line ( $self->git->remote('show', { n => 1 }, $remote) ) {
      chomp $line;
      return $1 if ($line =~ /^\s*(?:Fetch)?\s*URL:\s*(.*)/);
   }
   return;
}

42;
