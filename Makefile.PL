# $Id: Makefile.PL,v 1.5 2002/05/14 22:38:16 itz Exp $

use ExtUtils::MakeMaker;
use FileHandle;

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

# omit the stupid Makefile -> Makefile.old rule

our $fh_mm = FileHandle->new("<Makefile");
defined $fh_mm or die "can't open Makefile: $!";
our $fh_mm_tmp = FileHandle->new(">Makefile.tmp");
defined $fh_mm_tmp or die "can't write to Makefile.tmp: $!";
our $mm_line = $fh_mm->getline();
while ($mm_line !~ /MakeMaker makefile section/ ) {
    $fh_mm_tmp->print($mm_line);
    $mm_line = $fh_mm->getline();
}
while ($mm_line !~ /^\tfalse\s*$/ ) { 
    $mm_line = $fh_mm->getline();
}
$mm_line = $fh_mm->getline();
while ($mm_line) {
    $fh_mm_tmp->print($mm_line);
    $mm_line = $fh_mm->getline();
}

our $new_rulez = <<"EOF";

# This portion copied verbatim from Makefile.PL
Makefile : Makefile.PL \$(CONFIGDEP)
	\$(PERL) \"-I\$(PERL_ARCHLIB)\" \"-I\$(PERL_LIB)\"  Makefile.PL 

EOF

$fh_mm_tmp->print($new_rulez);
$fh_mm->close();
$fh_mm_tmp->close();

rename("Makefile.tmp", "Makefile") or die "Can't rename Makefile.tmp to Makefile: $!";
