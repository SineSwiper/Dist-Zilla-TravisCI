
use strict;
use warnings;

use 5.010001;

use ExtUtils::MakeMaker 6.30;



my %WriteMakefileArgs = (
  "ABSTRACT" => "Travis CI plugins for your DZIL-based distribution",
  "AUTHOR" => "Brendan Byrd <BBYRD\@CPAN.org>",
  "BUILD_REQUIRES" => {
    "Test::CheckDeps" => "0.002",
    "Test::UseAllModules" => "0.10"
  },
  "CONFIGURE_REQUIRES" => {},
  "DISTNAME" => "Dist-Zilla-TravisCI",
  "EXE_FILES" => [],
  "LICENSE" => "artistic_2",
  "NAME" => "Dist::Zilla::TravisCI",
  "PREREQ_PM" => {
    "Acme::Indent" => "0.01",
    "Dist::Zilla" => "1.093220",
    "Dist::Zilla::Plugin::Git::Check" => "1.093250",
    "Dist::Zilla::Role::Git::DirtyFiles" => "1.100740",
    "Dist::Zilla::Role::Git::LocalRepository" => "v0.1.1",
    "Dist::Zilla::Role::Git::Remote" => "v0.1.1",
    "Dist::Zilla::Role::Git::Remote::Branch" => "v0.1.1",
    "Dist::Zilla::Role::Git::Remote::Check" => "v0.1.1",
    "Dist::Zilla::Role::Git::Remote::Update" => "v0.1.1",
    "Dist::Zilla::Role::Git::Repo" => "1.113220",
    "Dist::Zilla::Role::MetaCPANInterfacer" => "0.90",
    "File::Slurp" => "9999.14",
    "List::AllUtils" => "0.01",
    "Moose" => "0.34",
    "Moose::Autobox" => "0.09",
    "MooseX::Has::Sugar" => "0.0100",
    "MooseX::Types::Moose" => 0,
    "sanity" => "0.91"
  },
  "VERSION" => "0.92",
  "test" => {
    "TESTS" => "t/*.t"
  }
);


unless ( eval { ExtUtils::MakeMaker->VERSION(6.56) } ) {
  my $br = delete $WriteMakefileArgs{BUILD_REQUIRES};
  my $pp = $WriteMakefileArgs{PREREQ_PM};
  for my $mod ( keys %$br ) {
    if ( exists $pp->{$mod} ) {
      $pp->{$mod} = $br->{$mod} if $br->{$mod} > $pp->{$mod};
    }
    else {
      $pp->{$mod} = $br->{$mod};
    }
  }
}

delete $WriteMakefileArgs{CONFIGURE_REQUIRES}
  unless eval { ExtUtils::MakeMaker->VERSION(6.52) };

WriteMakefile(%WriteMakefileArgs);



