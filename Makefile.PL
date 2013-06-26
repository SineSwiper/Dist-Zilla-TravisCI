
use strict;
use warnings;

use 5.010001;

use ExtUtils::MakeMaker 6.30;



my %WriteMakefileArgs = (
  "ABSTRACT" => "Travis CI plugins for your DZIL-based distribution",
  "AUTHOR" => "Brendan Byrd <bbyrd\@cpan.org>",
  "BUILD_REQUIRES" => {},
  "CONFIGURE_REQUIRES" => {},
  "DISTNAME" => "Dist-Zilla-TravisCI",
  "EXE_FILES" => [],
  "LICENSE" => "artistic_2",
  "NAME" => "Dist::Zilla::TravisCI",
  "PREREQ_PM" => {
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
    "YAML" => "0.67",
    "sanity" => "0.91"
  },
  "TEST_REQUIRES" => {
    "Dist::Zilla" => 0,
    "Test::CheckDeps" => "0.002",
    "Test::DZil" => "4.200002",
    "Test::More" => "0.94",
    "Test::Most" => "0.01"
  },
  "VERSION" => "1.04",
  "test" => {
    "TESTS" => "t/*.t"
  }
);


unless ( eval { ExtUtils::MakeMaker->VERSION(6.63_03) } ) {
  my $tr = delete $WriteMakefileArgs{TEST_REQUIRES};
  my $br = $WriteMakefileArgs{BUILD_REQUIRES};
  for my $mod ( keys %$tr ) {
    if ( exists $br->{$mod} ) {
      $br->{$mod} = $tr->{$mod} if $tr->{$mod} > $br->{$mod};
    }
    else {
      $br->{$mod} = $tr->{$mod};
    }
  }
}

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



