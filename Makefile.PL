# $Id: Makefile.PL 21 2006-04-21 05:20:33Z itz $

use ExtUtils::MakeMaker;

# this is here because otherwise Perl includes Emacs backup files (ie. *~)
our %pm_hash = ('lib/Mail/Sort.pm' => '$(INST_LIB)/Mail/Sort.pm',
                'lib/Mail/Sort/Dedupe.pm' => '$(INST_LIB)/Mail/Sort/Dedupe.pm',
                'lib/Mail/Sort/Base.pm' => '$(INST_LIB)/Mail/Sort/Base.pm'
                );

WriteMakefile(

              NAME                   => 'Mail::Sort',
              VERSION           => '20060414',
              PREREQ_PM              => {
                  'FileHandle'       => '2.00',
                  'POSIX'            => '1.03',
              },
              PM                     => \%pm_hash,
              MAN3PODS               => {'Sort.pod' => '$(INST_MAN3DIR)/Mail::Sort.3pm'},
              realclean             => {FILES => '$(shell find . -name "*~")' },
              );
