# vim:sw=2:tabstop=2:expandtab

package Wikiprep::revision;

use strict;
use Exporter 'import';
our @EXPORT_OK = qw( getWikiprepRevision getDumpDate getDatabaseName );
use FindBin;

sub getWikiprepRevision() {
  my $version;

  my $topdir = $FindBin::Bin;
  $topdir =~ s/tests-perl\/?//;

  # First try SVN...
  if( open(VERSION, "svnversion $topdir|") ) {
    $version = <VERSION>;
    chomp($version);
    close(VERSION);
  } else {
    $version = "exported";
  }

  if( $version eq "exported" ) {
    # No SVN version information. Check for git.
    if( open(VERSION, "git --git-dir $topdir/.git rev-parse HEAD|") ) {
      $version = <VERSION>;
      if( defined( $version ) ) {
        chomp($version);
        close(VERSION);
      } else {
        $version = "unknown";
      }
    } else {
      $version = "unknown";
    }
  }

  return $version;
}

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
