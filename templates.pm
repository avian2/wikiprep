# vim:sw=2:tabstop=2:expandtab

use strict;
use File::Path;

package templates;

sub prepare(\$) {
  my ($refToTemplateIncDir) = @_;

  mkdir($$refToTemplateIncDir);

  my $n = 1;
  do {
    my $path = "$$refToTemplateIncDir/$n";
    if( -d $path ) {
      File::Path::rmtree($path, 1, 0);
    }
    mkdir("$$refToTemplateIncDir/$n");
    $n++;
  } while($n < 10);
}

sub logPath(\$\$) {
  my ($refToTemplateIncDir, $refToTemplateId) = @_;

  my $prefix = substr($$refToTemplateId, 0, 1);

  return "$$refToTemplateIncDir/$prefix/$$refToTemplateId";
}

1
