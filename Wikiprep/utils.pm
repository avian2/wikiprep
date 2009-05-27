# vim:sw=2:tabstop=2:expandtab

package Wikiprep::utils;

use strict;
use Exporter 'import';
use Hash::Util qw( lock_hash );
our @EXPORT_OK = qw( encodeXmlChars getLinkIds removeDuplicatesAndSelf removeElements 
                     openOutputFile outputFilename openInputFile );

use File::Basename;
use File::Spec;
use IO::File;

use Log::Handler wikiprep => 'LOG';

my %XmlEntities = ('&' => 'amp', '"' => 'quot', "'" => 'apos', '<' => 'lt', '>' => 'gt');
lock_hash(%XmlEntities);

sub outputFilename {
  my ($inputFile, $outputFileSuffix, %options) = @_;

  $inputFile =~ s/\.[0-9]+$//;

  my ($inputFileBase, $inputFilePath, $inputFileSuffix) = fileparse($inputFile, 
                                                                    ".xml", ".xml.gz", ".xml.bz2");

  my $outputFile = File::Spec->catfile($inputFilePath, $inputFileBase . $outputFileSuffix);

  $outputFile .= sprintf(".%04d", $options{PART}) if defined( $options{PART} );

  return $outputFile;
}

sub openOutputFile {
  my ($inputFile, $outputFileSuffix, %options) = @_;

  my $outputFile = &outputFilename(@_);

  my $fh;
  if($options{COMPRESS}) {
    $fh = IO::File->new("| gzip > $outputFile.gz");
    die("Can't open pipe to gzip: $!") unless $fh;
  } else {
    $fh = IO::File->new("> $outputFile");
    die("Can't open $outputFile: $!") unless $fh;
  }

  $fh->binmode(":utf8");

  return $fh;
}

sub openInputFile {
  my ($inputFile) = @_;

  my $fh;
  if ($inputFile =~ /\.gz$/) {
    open($fh, "gzip -dc $inputFile|") or die "Cannot open $inputFile: $!";
  } elsif ($inputFile =~ /\.bz2$/) {
    open($fh, "bzip2 -dc $inputFile|") or die "Cannot open $inputFile: $!";
  } else {
    open($fh, "< $inputFile") or die "Cannot open $inputFile: $!";
  }

  return $fh;
}

sub encodeXmlChars(\$) {
  my ($refToStr) = @_;

  $$refToStr =~ s/([&"'<>])/&$XmlEntities{$1};/g;
}

sub getLinkIds(\@\@) {
  my ($refToLinkIds, $refToInternalLinks) = @_;

  for my $link (@$refToInternalLinks) {
    if( exists( $link->{targetId} ) ) {
      push(@$refToLinkIds, $link->{targetId});
    }
  }
}

# If specified, 'elementToRemove' contains an element that needs to be removed as well.
# For links, this ensures that a page does not link to itself. For categories, this
# ensures that a page is not categorized to itself. This parameter is obviously
# irrelevant for filtering URLs.
# 'elementToRemove' must be a numeric value (not string), since we're testing it with '==' (not 'eq')
sub removeDuplicatesAndSelf(\@$) {
  my ($refToArray, $elementToRemove) = @_;

  my %seen = ();
  my @uniq;

  my $item;
  foreach $item (@$refToArray) {
    if ( defined($elementToRemove) && ($item == $elementToRemove) ) {
      LOG->info("current page links or categorizes to itself - " . 
                             "link discarded ($elementToRemove)");
      next;
    }
    push(@uniq, $item) unless $seen{$item}++;
  }

  # overwrite the original array with the new one that does not contain duplicates
  @$refToArray = @uniq;
}

# Removes elements of the second list from the first list.
# For efficiency purposes, the second list is converted into a hash.
sub removeElements(\@\@) {
  my ($refToArray, $refToElementsToRemove) = @_;

  my %elementsToRemove = ();
  my @result;

  # Construct the hash table for fast lookups
  my $item;
  foreach $item (@$refToElementsToRemove) {
    $elementsToRemove{$item} = 1;
  }

  foreach $item (@$refToArray) {
    if ( ! defined($elementsToRemove{$item}) ) {
      push(@result, $item);
    }
  }

  # overwrite the original array with the new one
  @$refToArray = @result;
}

1;
