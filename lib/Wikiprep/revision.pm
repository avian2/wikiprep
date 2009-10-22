# vim:sw=2:tabstop=2:expandtab

package Wikiprep::revision;

use strict;
use Exporter 'import';
our @EXPORT_OK = qw( getDumpDate getDatabaseName );
use FindBin;

sub getDumpDate($) {
  my ($dumpFile) = @_;

  if($dumpFile =~ /[a-z]+-([0-9a-z_]+)-pages-articles.xml/) {
    return $1;
  } else {
    return "unknown";
  }
}

sub getDatabaseName($) {
  my ($dumpFile) = @_;

  if($dumpFile =~ /([a-z]+)-[0-9a-z_]+-pages-articles.xml/) {
    return $1;
  } else {
    return "unknown";
  }
}

1;
