# $Id: Makefile.PL,v 1.3 2001/10/15 06:56:59 itz Exp $

use ExtUtils::MakeMaker;

WriteMakefile(

              NAME                   => 'Mail::Sort',
              VERSION_FROM           => 'lib/Mail/Sort.pm',
              PREREQ_PM              => {
                  'FileHandle'       => '2.00',
                  'Mail::Internet'   => '1.33',
                  'Mail::Header'     => '1.19',
                  'POSIX'            => '1.03',
              }
              
              );
