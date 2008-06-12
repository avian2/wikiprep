# vim:sw=2:tabstop=2:expandtab

use strict;

package utils;

# See http://www.perlmonks.org/?node_id=2258 for performance comparisson

sub trimWhitespaceBothSides {
  $_ = shift;
  s/^\s+//;
  s/\s+$//;

  return $_;
}

1
