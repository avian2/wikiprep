# vim:sw=2:tabstop=2:expandtab

use strict;
use FindBin;

package revision;

sub getWikiprepRevision() {
  open(VERSION, "svnversion $FindBin::Bin|");
  my $version = <VERSION>;
  chomp($version);
  close(VERSION);

  return $version;
}

sub getDumpDate($) {
  my ($dumpFile) = @_;

  if($dumpFile =~ /[a-z]+-([0-9]+)-pages-articles.xml$/) {
    return $1;
  } else {
    return "unknown";
  }
}

sub writeVersion($$) {
  my ($versionFile, $dumpFile) = @_;

  open(VERSIONF, "> $versionFile") or die "Cannot open $versionFile: $!";

  my $dumpDate = &getDumpDate($dumpFile);
  my $svnrev = &getWikiprepRevision();

  print(VERSIONF "mediawiki-dump-date: $dumpDate\n");
  print(VERSIONF "wikiprep-revision: $svnrev\n");

  close(VERSIONF);
}

1
