use ExtUtils::MakeMaker;
# See lib/ExtUtils/MakeMaker.pm for details of how to influence
# the contents of the Makefile that is written.
WriteMakefile(
    NAME         => 'Gearman::Client::Danga',
    VERSION_FROM => 'lib/Gearman/Client/Danga.pm', # finds $VERSION
    PREREQ_PM    => {
                     'Test::Simple' => 0.44,
                    },
    ( $] >= 5.005 ?
      (
        AUTHOR       => 'Jonathan Steinert (hachi@cpan.org)',
        ABSTRACT_FROM => 'lib/Gearman/Client/Danga.pm',
      ) : ()),
    dist => {
      COMPRESS => 'gzip -9',
      SUFFIX   => 'gz',
      PREOP    => q{pod2text lib/Gearman/Client/Danga.pm > ./$(DISTNAME)-$(VERSION)/README},
    },
);
