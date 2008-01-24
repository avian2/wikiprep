# vim:sw=2:tabstop=2:expandtab

use strict;

package revision;

sub getRevision() {
  $svnrev = '$Rev$';

  $svnrev =~ s/.*([0-9]+).*/\1/;

  return $svnrev;
}

1
