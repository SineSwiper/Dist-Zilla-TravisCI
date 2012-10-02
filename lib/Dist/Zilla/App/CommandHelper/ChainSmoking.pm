package Dist::Zilla::App::CommandHelper::ChainSmoking;

our $VERSION = '0.95'; # VERSION
# ABSTRACT: Helper class for chainsmoke command

use sanity;
use Moose;

use List::AllUtils 'first';
use Dist::Zilla::Plugin::TravisYML;
use Dist::Zilla::Plugin::Git::Check;

# dzil chainsmoke has to pass this, and we can figure out the rest
has app => ( isa => 'Object', is => 'ro', required => 1 );

sub zilla { $_[0]->app->zilla }

has logger => (
   is   => 'ro',
   lazy => 1,
   handles => [ qw(log log_debug log_fatal) ],
   default => sub { $_[0]->app->chrome->logger; },
);

has branch => ( isa => 'Str', is => 'ro', lazy => 1, default => sub {
   my ($branch) = shift->git->symbolic_ref(qw(-q HEAD));
   $branch =~ s|^refs/heads/||;
   return $branch;
} );

### HACK: Needed for DirtyFiles, though this is really only used for Plugins ###
sub mvp_multivalue_args { }

with 'Dist::Zilla::Role::Git::Repo';
with 'Dist::Zilla::Role::Git::DirtyFiles';
sub _build_allow_dirty { [ ] }  # overload

with 'Dist::Zilla::Role::Git::LocalRepository';
with 'Dist::Zilla::Role::Git::Remote';
with 'Dist::Zilla::Role::Git::Remote::Branch';
with 'Dist::Zilla::Role::Git::Remote::Check';
with 'Dist::Zilla::Role::Git::Remote::Update';

has '+_remote_branch' => ( lazy => 1, default => sub { shift->branch } );

with 'Dist::Zilla::Role::TravisYML';

sub chainsmoke {
   my ($self, $opt) = @_;
   
   # have Git::Check verify there are no dirty files, etc.
   $self->check_local;
   
   # have Git::Remote::Check verify the branch is up to date
   unless ($self->is_remote_branch_new) {
      $self->do_update(1);
      $self->remote_update;
      $self->check_remote;
   }
   
   # checks are done, so create the YML
   my $yml_creator = first { $_->isa('Dist::Zilla::Plugin::TravisYML') } @{$self->zilla->plugins};
   
   # doesn't appear to be in dist.ini, so set based on $opt
   $self->build_branch('');
   unless ($yml_creator) {
      if ($opt->silentci) {
         $self->notify_email([0]);
         $self->notify_irc  ([0]);
      }
      $self->mvdt(1) if $opt->mvdt;
   }
   # else modify the options via the plugin
   else {
      $self->notify_email ($opt->silentci ? [0] : $yml_creator->notify_email );
      $self->notify_irc   ($opt->silentci ? [0] : $yml_creator->notify_irc   );
      $self->mvdt         ($opt->mvdt     ? 1   : $yml_creator->mvdt         );
   }
   
   # in order to access the prereqs and distmeta in general, 
   # we need to partially run through the build process
   
   ### TODO: Make some extra checks to see if we even need the distmeta object. ###
   ###       We only need it for notification detection and MVDT.               ###
   $self->log("\nStarting pre-build...");
   $self->prebuild;
   $self->log("Done with pre-build\n");
   
   # actual creation
   $self->build_travis_yml;
   $self->log("YML file built");
   
   # now for the Git commit/push
   $self->git->add('.travis.yml');
   $self->log_debug($_) for $self->git->commit(
      { message => '"Chain smoking for local branch '.$self->branch.'"' },
      '--allow-empty',  # because it might be ran multiple times without changes
   );
   $self->log('Commited');
   
   $self->log_debug($_) for $self->git->push( $self->remote, 'HEAD:'.$self->_remote_branch );   
   $self->log('Pushed');
}

### LAZY: This is pretty much a straight copy of Dist::Zilla::Plugin::Git::Check. ###

sub check_local {
   my $self = shift;
   my $git = $self->git;
   my @output;
 
   # fetch current branch
   my $branch = first { s/^\*\s+// } $git->branch;
 
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

sub is_remote_branch_new {
   my $self = shift;
   my $git  = $self->git;
   my $rb   = $self->remote_branch;
   return ( first { /^\s*\Q$rb\E\s*$/ } $git->branch('--remotes') ) ? 0 : 1;
}

### FIXME: Mostly a copy from D:Z:D:B->build_in; will put in ticket to add in a separate method ###
sub prebuild {
   my $self = shift;
   my $zilla = $self->zilla;

   use Moose::Autobox 0.09; # ->flatten
   
   $_->before_build     for $zilla->plugins_with(-BeforeBuild )->flatten;
   $_->gather_files     for $zilla->plugins_with(-FileGatherer)->flatten;
   $_->prune_files      for $zilla->plugins_with(-FilePruner  )->flatten;
   $_->munge_files      for $zilla->plugins_with(-FileMunger  )->flatten;
   $_->register_prereqs for $zilla->plugins_with(-PrereqSource)->flatten;
   
   $zilla->prereqs->finalize;
}

42;
 


=pod

=encoding utf-8

=head1 NAME

Dist::Zilla::App::CommandHelper::ChainSmoking - Helper class for chainsmoke command

=head1 AVAILABILITY

The project homepage is L<https://github.com/SineSwiper/Dist-Zilla-TravisCI/wiki>.

The latest version of this module is available from the Comprehensive Perl
Archive Network (CPAN). Visit L<http://www.perl.com/CPAN/> to find a CPAN
site near you, or see L<https://metacpan.org/module/Dist::Zilla::TravisCI/>.

=head1 AUTHOR

Brendan Byrd <BBYRD@CPAN.org>

=head1 COPYRIGHT AND LICENSE

This software is Copyright (c) 2012 by Brendan Byrd.

This is free software, licensed under:

  The Artistic License 2.0 (GPL Compatible)

=cut


__END__
