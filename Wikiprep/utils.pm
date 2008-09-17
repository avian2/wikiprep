# vim:sw=2:tabstop=2:expandtab

package Wikiprep::utils;

use strict;
use Exporter 'import';
our @EXPORT_OK = qw( trimWhitespaceBothSides );

# See http://www.perlmonks.org/?node_id=2258 for performance comparisson

sub trimWhitespaceBothSides {
  $_ = shift;
  s/^\s+//;
  s/\s+$//;

  return $_;
}

1
