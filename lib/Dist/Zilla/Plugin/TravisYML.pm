package Dist::Zilla::Plugin::TravisYML;

our $VERSION = '0.90'; # VERSION
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
with 'Dist::Zilla::Role::TravisYML';

around mvp_multivalue_args => sub {
   my ($orig, $self) = @_;
   
   my @start = $self->$orig;
   return (@start, 'notify_email', 'notify_irc');
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
   $self->build_travis_yml(1) if $self->build_branch;
}

__PACKAGE__->meta->make_immutable;
42;
 


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
    push_to = origin
    push_to = origin build/master:build/master

=head1 DESCRIPTION

This plugin creates a C<<< .travis.yml >>> file in your distro for CI smoke testing (or what we like
to call "[chain smokingE<verbar>Dist::Zilla::App::Command::chainsmokeE<sol>CHAIN-SMOKING-]").  It will also
(optionally) create a separate C<<< .travis.yml >>> file for your build directory after a release.

Why two files?  Because chain smoking via DZIL will work a lot differently than a traditional 
CE<lt>Makefile.PL; makeE<gt>.  This tests both your distribution repo environment as well as what a 
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

=head2 mvdt

Turning this on enables L<Minimum Version Dependency Testing|Dist::Zilla::TravisCI::MVDT>.  This
will make your YML file less of a static file, as it will now include commands to forcefully
B<downgrade> your dependencies to the lowest version that your prereqs said they would be able
to use.

While going through the MVDT process is recommended, it can be a royal pain-in-the-ass
sometimes, so this option isn't on by default.  It's HIGHLY recommended that you read the above
doc first to get an idea of what you're diving into.

This applies to both YML files.

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

