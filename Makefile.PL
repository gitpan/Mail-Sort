# $Id: Makefile.PL,v 1.6 2003/03/18 17:15:47 itz Exp $

use ExtUtils::MakeMaker;

# this is here because otherwise Perl includes Emacs backup files (ie. *~)
our %pm_hash = ('lib/Mail/Sort.pm' => '$(INST_LIB)/Mail/Sort.pm');

WriteMakefile(

              NAME                   => 'Mail::Sort',
              VERSION_FROM           => 'lib/Mail/Sort.pm',
              PREREQ_PM              => {
                  'FileHandle'       => '2.00',
                  'Mail::Internet'   => '1.33',
                  'Mail::Header'     => '1.19',
                  'POSIX'            => '1.03',
              },
              PM                     => \%pm_hash,
              MAN3PODS               => {'Sort.pod' => '$(INST_MAN3DIR)/Mail::Sort.3pm'},
              realclean             => {FILES => '$(shell find . -name "*~")' },
              );
