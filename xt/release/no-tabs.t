use strict;
use warnings;

# this test was generated with Dist::Zilla::Plugin::NoTabsTests 0.05

use Test::More 0.88;
use Test::NoTabs;

my @files = (
    'lib/Dist/Zilla/App/Command/chainsmoke.pm',
    'lib/Dist/Zilla/App/CommandHelper/ChainSmoking.pm',
    'lib/Dist/Zilla/Plugin/TravisYML.pm',
    'lib/Dist/Zilla/Role/TravisYML.pm',
    'lib/Dist/Zilla/TravisCI.pod',
    'lib/Dist/Zilla/TravisCI/MVDT.pod'
);

notabs_ok($_) foreach @files;
done_testing;
