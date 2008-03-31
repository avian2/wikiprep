# vim:sw=2:tabstop=2:expandtab

use strict;
use FindBin;

package revision;

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

  if($dumpFile =~ /[a-z]+-([0-9a-z_]+)-pages-articles.xml$/) {
    return $1;
  } else {
    return "unknown";
  }
}

sub getDatabaseName($) {
  my ($dumpFile) = @_;

  if($dumpFile =~ /([a-z]+)-[0-9a-z_]+-pages-articles.xml$/) {
    return $1;
  } else {
    return "unknown";
  }
}

sub writeVersion($$) {
  my ($versionFile, $dumpFile) = @_;

  open(VERSIONF, "> $versionFile") or die "Cannot open $versionFile: $!";

  my $dumpDate = &getDumpDate($dumpFile);
  my $dumpName = &getDatabaseName($dumpFile);
  my $svnrev = &getWikiprepRevision();

  print(VERSIONF "$dumpName-mediawiki-dump-date: $dumpDate\n");
  print(VERSIONF "$dumpName-wikiprep-revision: $svnrev\n");

  close(VERSIONF);
}

1
