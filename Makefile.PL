
use strict;
use warnings;



use ExtUtils::MakeMaker 6.31;



my %WriteMakefileArgs = (
  'ABSTRACT' => 'Transport agnostic JSON RPC helper objects',
  'AUTHOR' => 'Yuval Kogman <nothingmuch@woobling.org>',
  'BUILD_REQUIRES' => {
    'Test::Exception' => '0'
  },
  'CONFIGURE_REQUIRES' => {
    'ExtUtils::MakeMaker' => '6.31'
  },
  'DISTNAME' => 'JSON-RPC-Common',
  'EXE_FILES' => [],
  'LICENSE' => 'perl',
  'NAME' => 'JSON::RPC::Common',
  'PREREQ_PM' => {
    'HTTP::Request' => '0',
    'JSON' => '2.11',
    'MIME::Base64' => '0',
    'Moose' => '0.48',
    'MooseX::Types' => '0',
    'MooseX::Types::Moose' => '0',
    'Try::Tiny' => '0',
    'URI::QueryParam' => '0',
    'namespace::clean' => '0.20'
  },
  'VERSION' => '0.10',
  'test' => {
    'TESTS' => 't/*.t'
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



