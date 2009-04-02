#!/usr/bin/perl -w
###############################################################################
# vim:sw=2:tabstop=2:expandtab
#
# wikiprep.pl - Preprocess Wikipedia XML dumps
# Copyright (C) 2007 Evgeniy Gabrilovich (gabr@cs.technion.ac.il)
# Copyright (C) 2008, 2009 Tomaz Solc (tomaz.solc@tablix.org)
#
#    This program is free software; you can redistribute it and/or modify
#    it under the terms of the GNU General Public License as published by
#    the Free Software Foundation; either version 2 of the License, or
#    (at your option) any later version.
#
#    This program is distributed in the hope that it will be useful,
#    but WITHOUT ANY WARRANTY; without even the implied warranty of
#    MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
#    GNU General Public License for more details.
#
#    You should have received a copy of the GNU General Public License
#    along with this program; if not, write to the Free Software
#    Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston, MA  02110-1301, USA,
#    or see <http://www.gnu.org/licenses/> and
#    <http://www.fsf.org/licensing/licenses/info/GPLv2.html>
#
###############################################################################

use strict;
use warnings;

use File::Basename;
use File::Spec;

use Getopt::Long;
use Time::localtime;
use Parse::MediaWikiDump;
use Log::Handler wikiprep => 'LOG';

use FindBin;
use lib "$FindBin::Bin";

use Wikiprep::Config;
use Wikiprep::Link qw( %title2id %redir resolveLink parseRedirect extractWikiLinks );
use Wikiprep::Related qw( identifyRelatedArticles );
use Wikiprep::Disambig qw( isDisambiguation parseDisambig );
use Wikiprep::Namespace qw( loadNamespaces normalizeTitle isNamespaceOk );
use Wikiprep::images qw( convertGalleryToLink convertImagemapToLink );
use Wikiprep::revision qw( getWikiprepRevision getDumpDate getDatabaseName );
use Wikiprep::css qw( removeMetadata );
use Wikiprep::utils qw( encodeXmlChars getLinkIds removeDuplicatesAndSelf removeElements );

# Command line options
my $optFile;
my $optDontExtractUrls;
my $optCompress;
our $optPurePerl;

my $optConfigName = "enwiki";
my $optOutputFormat = "legacy";
my $optLogLevel = "notice";

my $optShowLicense;
my $optShowVersion;

# Global constants
my $licenseFile = "COPYING";
my $VERSION = "3.0";

# Object that takes care of writing output files
our $output;

# Input file
my $inputFilePath;
my $inputFileBase;
my $inputFileSuffix;

# Needed for benchmarking and ETA calculation
my $totalPageCount = 0;
my $totalByteCount = 0;

my %catHierarchy;       # each category is associated with a list of its immediate descendants
my %statCategories;     # number of pages classified under each category
my %statIncomingLinks;  # number of links incoming to each page

sub parseOptions {

  GetOptions('f=s'        => \$optFile,

             'license'    => \$optShowLicense,
             'version'    => \$optShowVersion,

             'nourls'     => \$optDontExtractUrls,
             'log=s'      => \$optLogLevel,
             'compress'   => \$optCompress,
             'config=s'   => \$optConfigName,
             'format=s'   => \$optOutputFormat,
             'pureperl=s' => \$optPurePerl );

}

sub loadModules {
  eval { Wikiprep::Config::init($optConfigName) };
  die "Can't load config $optConfigName: $@" if $@;

  my $outputType = sprintf("Wikiprep::Output::%s", ucfirst( lc( $optOutputFormat ) ) );

  my $outputModule = $outputType;
  $outputModule =~ s/::/\//g;
  $outputModule .= ".pm";

  binmode(STDOUT,  ':utf8');
  binmode(STDERR,  ':utf8');

  eval { require $outputModule };
  die "Can't load support for output format $optOutputFormat: $@" if $@;

  $output = $outputType->new( File::Spec->catfile($inputFilePath, $inputFileBase), 
                              $optFile, 
                              COMPRESS => $optCompress );

  require Wikiprep::Templates; 
  use vars qw( %templates );
  Wikiprep::Templates->import qw( %templates includeTemplates );
}

sub initLog {

  LOG->add(
    screen => {
      maxlevel        => 'notice',
      newline         => 1
    } );

  LOG->add(
    file   => {
      filename        => File::Spec->catfile($inputFilePath, "$inputFileBase.log"),
      mode            => 'trunc',
      utf8            => 1,
  
      maxlevel        => $optLogLevel,
      newline         => 1,
    } );

  LOG->add(
    file   => {
      filename        => File::Spec->catfile($inputFilePath, "$inputFileBase.profile"),
      mode            => 'trunc',
      utf8            => 1,
  
      maxlevel        => 'info',
      minlevel        => 'info',
      newline         => 1,
      filter_message  => qr/transforming page took/,
    } );

  my $revision = &getWikiprepRevision;
  my $dumpDate = &getDumpDate($optFile);
  my $dumpName = &getDatabaseName($optFile);

  LOG->info( "This is Wikiprep $VERSION ($revision)" );
  LOG->info( "Processing $dumpName version $dumpDate" );
}

sub main {

  &parseOptions;

  if( $optShowLicense ) {
    if( -e $licenseFile ) {
      print "See file $licenseFile for more details.\n";
    } else {
      print "Please see http://www.gnu.org/licenses/ and\n";
      print "http://www.fsf.org/licensing/licenses/info/GPLv2.html\n";
    }
    exit 0;
  } elsif( $optShowVersion ) {
    print "Wikiprep version $VERSION\n";
    exit 0;
  } elsif( not $optFile ) {
    &printUsage();
    exit 1;
  }

  if(! -e $optFile ) {
    die "Input file '$optFile' does not exist!\n";
  }

  ($inputFileBase, $inputFilePath, $inputFileSuffix) = fileparse($optFile, ".xml", ".xml.gz", ".xml.bz2");

  &loadModules;
  &initLog;

  my $startTime = time;

  &prescan();

  &Wikiprep::Link::prescanFinished();
  &Wikiprep::Templates::prescanFinished();

  $output->writeRedirects(\%redir, \%title2id, \%templates);

  &transform();

  &writeStatistics();
  &writeCategoryHierarchy();

  $output->finish();

  my $elapsed = time - $startTime;

  LOG->notice( sprintf("Processing took %d:%02d:%02d", $elapsed/3600, ($elapsed / 60) % 60, $elapsed % 60) );
}

# Hogwarts needs the anchor text file to be sorted in the increading order of target page id.
# The file is originally sorted by source page id (second field in each line).
# We now use stable (-s) numeric (-n) sort on the first field (-k 1,1).
# This way, the resultant file will be sorted on the target page id (first field) as primary key,
# and on the source page id (second field) as secondary key.
# system("sort -s -n -k 1,1 $anchorTextFile > $anchorTextFile.sorted");


##### Subroutines #####

sub writeStatistics() {
  my $statCategoriesFile = File::Spec->catfile($inputFilePath, "$inputFileBase.stat.categories");
  my $statIncomingLinksFile = File::Spec->catfile($inputFilePath, "$inputFileBase.stat.inlinks");

  open(STAT_CATS, "> $statCategoriesFile") or die "Cannot open $statCategoriesFile";
  print STAT_CATS "# Line format: <CategoryId (= page id)>  <Number of pages in this category>\n",
                  "# Here we count the *pages* that belong to this category, i.e., articles AND\n",
                  "# sub-categories of this category (but not the articles in the sub-categories).\n",
                  "\n\n";

  my $cat;
#  foreach $cat ( sort { $statCategories{$b} <=> $statCategories{$a} }
#                 keys(%statCategories) ) {
#    print STAT_CATS "$cat\t$statCategories{$cat}\n";
#  }
  foreach $cat ( keys(%statCategories) ) {
    print STAT_CATS "$cat\t$statCategories{$cat}\n";
  }
  close(STAT_CATS);

  open(STAT_INLINKS, "> $statIncomingLinksFile") or die "Cannot open $statIncomingLinksFile";
  print STAT_INLINKS "# Line format: <Target page id>  <Number of links to it from other pages>\n\n\n";

  my $destination;
#  foreach $destination ( sort { $statIncomingLinks{$b} <=> $statIncomingLinks{$a} }
#                         keys(%statIncomingLinks) ) {
#    print STAT_INLINKS "$destination\t$statIncomingLinks{$destination}\n";
#  }
  foreach $destination ( keys(%statIncomingLinks) ) {
    print STAT_INLINKS "$destination\t$statIncomingLinks{$destination}\n";
  }

  close(STAT_INLINKS);
}

sub writeCategoryHierarchy() {
  my $catHierarchyFile = File::Spec->catfile($inputFilePath, "$inputFileBase.cat_hier");

  open(CAT_HIER, "> $catHierarchyFile") or die "Cannot open $catHierarchyFile";
  print CAT_HIER "# Line format: <Category id>  <List of ids of immediate descendants>\n\n\n";

  my $cat;
#  foreach $cat ( sort { $catHierarchy{$a} <=> $catHierarchy{$b} }
#                 keys(%catHierarchy) ) {
#    print CAT_HIER "$cat\t", join(" ", @{$catHierarchy{$cat}}), "\n";
#  }
  foreach $cat ( keys(%catHierarchy) ) {
    print CAT_HIER "$cat\t", join(" ", @{$catHierarchy{$cat}}), "\n";
  }

  close(CAT_HIER);
}

# build id <-> title mappings and redirection table,
# as well as load templates
sub prescan() {
  # re-open the input XML file
  if ($optFile =~ /\.gz$/) {
    open(INF, "gzip -dc $optFile|") or die "Cannot open $optFile: $!";
  } elsif ($optFile =~ /\.bz2$/) {
    open(INF, "bzip2 -dc $optFile|") or die "Cannot open $optFile: $!";
  } else {
    open(INF, "< $optFile") or die "Cannot open $optFile: $!";
  }

  my $pages = Parse::MediaWikiDump::Pages->new(\*INF);

  my @interwikiNamespaces = keys( %Wikiprep::Config::okNamespacesForInterwikiLinks );
  &loadNamespaces($pages, \@interwikiNamespaces );

  my $counter = 0;
  
  my %idexists;

  my $mwpage;
  while (defined($mwpage = $pages->page)) {
    my $id = $mwpage->id;

    $counter++;

    $totalPageCount++;
    $totalByteCount+=length(${$mwpage->text});

    my $title = $mwpage->title;
    &normalizeTitle(\$title);

    if ( exists($idexists{$id}) ) {
      LOG->warning("ID $id already encountered before (title $title)");
      next;
    }
    $idexists{$id} = 1;

    next unless &Wikiprep::Link::prescan(\$title, \$id, $mwpage);

    &Wikiprep::Templates::prescan(\$title, \$id, $mwpage);
  }

  close(INF);
  LOG->info("prescanning complete ($counter pages)");
  LOG->notice("total $totalPageCount pages ($totalByteCount bytes)");
}

sub transform() {
  # re-open the input XML file
  if ($optFile =~ /\.gz$/) {
    open(INF, "gzip -dc $optFile|") or die "Cannot open $optFile: $!";
  } elsif ($optFile =~ /\.bz2$/) {
    open(INF, "bzip2 -dc $optFile|") or die "Cannot open $optFile: $!";
  } else {
    open(INF, "< $optFile") or die "Cannot open $optFile: $!";
  }
  my $mwpages = Parse::MediaWikiDump::Pages->new(\*INF);

  my $categoryNamespace = $Wikiprep::Config::categoryNamespace;
  my $imageNamespace = $Wikiprep::Config::imageNamespace;

  my $processedPageCount = 0;
  my $processedByteCount = 0;

  my $startTime = time - 1;
  my $lastDisplayTime = $startTime;

  my $mwpage;
  while (defined($mwpage = $mwpages->page)) {

    $processedPageCount++;
    $processedByteCount += length(${$mwpage->text});

    my $page = {};

    $page->{startTime} = time;

    if( $page->{startTime} - $lastDisplayTime > 5 ) {

      $lastDisplayTime = $page->{startTime};

      my $bytesPerSecond = $processedByteCount / ( $page->{startTime} - $startTime );
      my $percentDone = 100.0 * $processedByteCount / $totalByteCount;
      my $secondsLeft = ( $totalByteCount - $processedByteCount ) / $bytesPerSecond;

      my $hoursLeft = $secondsLeft/3600;

      printf "At %.1f%% (%.0f bytes/s) ETA %.1f hours \r", $percentDone, $bytesPerSecond, $hoursLeft;
      STDOUT->flush();
    }

    $page->{id} = $mwpage->id;
    $page->{timestamp} = $mwpage->timestamp;

    # next if( $id != 1192748);

    LOG->debug("transforming page (ID $page->{id})");

    if ( defined( &parseRedirect($mwpage) ) ) {
      next; # we've already loaded all redirects in the prescanning phase
    }

    if ( ! &isNamespaceOk( $mwpage->namespace, \%Wikiprep::Config::okNamespacesForTransforming) ) {
      next; # we're only interested in pages from certain namespaces
    }

    my $title = $mwpage->title;
    &normalizeTitle(\$title);

    # see the comment about empty titles in function 'prescan'
    if (length($title) == 0) {
      LOG->debug("skipping page with empty title (ID $page->{id})");
      next;
    }

    $page->{title} = $title;

    my $text = ${$mwpage->text};

    # text length BEFORE any transformations
    $page->{orgLength} = length($text);

    # Remove comments (<!-- ... -->) from text. This is best done as early as possible so
    # that it doesn't slow down the rest of the code.
      
    # Comments can easily span several lines, so we use the "/s" modifier.

    $text =~ s/<!--(?:.*?)-->//sg;

    # Enable this to parse Uncyclopedia (<choose> ... </choose> is a
    # MediaWiki extension they use that selects random text - wikiprep
    # creates huge pages if we don't remove it)

    # $text =~ s/<choose[^>]*>(?:.*?)<\/choose[^>]*>/ /sg;

    # The check for stub must be done BEFORE any further processing,
    # because stubs indicators are templates, and templates are substituted.
    if ( $text =~ m/stub}}/i ) {
      $page->{isStub} = 1;
    } else {
      $page->{isStub} = 0;
    }

    $page->{text} = $text;

    # Parse disambiguation pages before template substitution because disambig
    # indicators are also templates.
    if ( &isDisambiguation($mwpage) ) {
      LOG->debug("parsing as a disambiguation page");

      &parseDisambig($page);

      $page->{isDisambig} = 1;
    } else {
      $page->{isDisambig} = 0;
    }

    $page->{templates} = {};
    $page->{text} = &includeTemplates($page, $page->{text}, 0);

    # This function only examines the contents of '$text', but doesn't change it.
    &identifyRelatedArticles($page);

    # We process categories directly, because '$page->categories' ignores
    # categories inherited from included templates
    &extractCategories($page);

    # Categories are listed at the end of articles, and therefore may mistakenly
    # be added to the list of related articles (which often appear in the last
    # section such as "See also"). To avoid this, we explicitly remove all categories
    # from the list of related links, and only then record the list of related links
    # to the file.
    &removeElements($page->{relatedArticles}, $page->{categories});

    &convertGalleryToLink(\$page->{text});
    &convertImagemapToLink(\$page->{text});

    # Remove <div class="metadata"> ... </div> and similar CSS classes that do not
    # contain usable text for us.
    &removeMetadata(\$page->{text});

    $page->{internalLinks} = [];
    $page->{interwikiLinks} = [];

    my @interwikiArray;

    &extractWikiLinks(\$page->{text}, $page->{internalLinks}, \@interwikiArray);

    use Data::Dumper;
    #print Dumper($page->{internalLinks});

    my @internalLinks;
    &getLinkIds(\@internalLinks, $page->{internalLinks});
    &removeDuplicatesAndSelf(\@internalLinks, $page->{id});

    if ( ! $optDontExtractUrls ) {
      &extractUrls($page);
    }

    &postprocessText(\$page->{text}, \@interwikiArray);

    # text length AFTER all transformations
    $page->{newLength} = length($page->{text});

    &updateStatistics($page->{categories}, \@internalLinks);

    if ($page->{title} =~ /^$categoryNamespace:/) {
      &updateCategoryHierarchy($page->{id}, $page->{categories});
      $page->{isCategory} = 1;
    } else {
      $page->{isCategory} = 0;
    }

    if ($page->{title} =~ /^$imageNamespace:/) {
      $page->{isImage} = 1;
    } else {
      $page->{isImage} = 0;
    }

    $output->newPage($page);

    my $pageFinishedTime = time;

    LOG->info( sprintf("transforming page took %d seconds (ID %d)", $pageFinishedTime - $page->{startTime}, 
               $page->{id}) );
  }
  print "\n";
  close(INF);
}

sub updateStatistics(\@\@) {
  my ($refToCategories, $refToInternalLinks) = @_;

  my $cat;
  foreach $cat (@$refToCategories) {
    $statCategories{$cat}++;
  }

  my $link;
  foreach $link (@$refToInternalLinks) {
    $statIncomingLinks{$link}++;
  }
}

sub updateCategoryHierarchy($\@) {
  # The list of categories passed as a parameter is actually the list of parent categories
  # for the current category
  my ($childId, $refToParentCategories) = @_;

  my $parentCat;
  foreach $parentCat (@$refToParentCategories) {
    if ( exists($catHierarchy{$parentCat}) ) {
      push(@{$catHierarchy{$parentCat}}, $childId);
    } else {
      # create a new array with '$childId' as the only child (for now) of '$parentCat'
      my @arr;
      push(@arr, $childId);
      $catHierarchy{$parentCat} = [ @arr ];
    }
  }
}

sub extractCategories(\%) {
  my ($page) = @_;

  # Remember that namespace names are case-insensitive, hence we're matching with "/i".
  # The first parameter to 'collectCategory' is passed by value rather than by reference,
  # because it might be dangerous to pass a reference to $1 in case it might get modified
  # (with unclear consequences).
  my $categoryNamespace = $Wikiprep::Config::categoryNamespace;

  $page->{categories} = [];

  $page->{text} =~ s/\[\[\s*($categoryNamespace:.*?)\]\]/&collectCategory($1, $page)/ieg;

  # We don't accumulate categories directly in a hash table, since this would not preserve
  # their original order of appearance.
  &removeDuplicatesAndSelf($page->{categories}, $page->{id});
}

sub collectCategory($\@) {
  my ($catName, $page) = @_;

  if ($catName =~ /^(.*)\|/) {
    # Some categories contain a sort key, e.g., [[Category:Whatever|*]] or [[Category:Whatever| ]]
    # In such a case, take only the category name itself.
    $catName = $1;
  }

  &normalizeTitle(\$catName);

  my $catId = &resolveLink(\$catName);
  if ( defined($catId) ) {
    push(@{$page->{categories}}, $catId);
  } else {
    LOG->info("unknown category '$catName'");
  }

  # The return value is just a space, because we remove categories from the text
  # after we collected them
  " ";
}

BEGIN {
  # Allowed URL protocols (copied from DefaultSettings.php)

  # Note that Wikipedia is case sensitive regarding URL protocols (e.g., [Http://...] will not produce 
  # an external link) 

  my %urlProtocols = ( 'http' => 1, 'https' => 1, 'ftp' => 1, 'irc' => 1, 'gopher' => 1, 'telnet' => 1, 
                       'nntp' => 1, 'worldwind' => 1, 'mailto' => 1, 'news' => 1 );

  # A regex that matches all valid URLs. The first group is
  my $urlRegex = qr/[a-z]+:(?:[\w!\$\&\'()*+,-.\/:;=?\@\_`~]|%[a-fA-F0-9]{2})+/;

  # MediaWiki supports two kinds of external links: implicit and explicit.

  # Explicit links can have anchors, and have format like [http://www.cnn.com CNN]. Anchor is the text from
  # the first whitespace to the end of the bracketed expression.

  # Note that no whitespace is allowed before the URL.
  my $urlSequence1 = qr/\[($urlRegex)(.*?)\]/;

  # Implicit links are normal text that is recognized as a valid URL.
  my $urlSequence2 = qr/($urlRegex)/;

  sub extractUrls(\%) {
    my ($page) = @_;

    $page->{externalLinks} = [];
    $page->{bareUrls} = [];

    # First we handle the case of URLs enclosed in single brackets, with or without the description.
    # Examples: [http://www.cnn.com], [ http://www.cnn.com  ], [http://www.cnn.com  CNN Web site]
    $page->{text} =~ s/$urlSequence1/&collectUrlFromBrackets($1, $2, $page)/eg;

    # Now we handle standalone URLs (those not enclosed in brackets)
    # The $urlTemrinator is matched via positive lookahead (?=...) in order not to remove
    # the terminator symbol itself, but rather only the URL.
    $page->{text} =~ s/$urlSequence2/&collectStandaloneUrl($1, $page)/eg;

    &removeDuplicatesAndSelf($page->{bareUrls}, undef);
  }

  sub collectUrlFromBrackets($$\%) {
    my ($url, $anchor, $page) = @_;

    # Extract protocol - this is the part of the string before the first ':' because of the
    # $urlRegex above.
   
    my @temp = split(/:/, $url, 2);
    my $urlProtocol = $temp[0];

    if( exists( $urlProtocols{$urlProtocol} ) ) {
      push(@{$page->{bareUrls}}, $url);

      my $anchorTrimmed = $anchor;

      # Trim whitespace;
      $anchorTrimmed =~ s/^\s+//;
      $anchorTrimmed =~ s/\s+$//;

      # See if there is anything left of the anchor and log to file
      if( length( $anchorTrimmed ) > 0 ) {
        push(@{$page->{externalLinks}}, { anchor => $anchorTrimmed, url => $url } );
      } else {
        push(@{$page->{externalLinks}}, { url => $url } );
      }
      return $anchor;
    } else {
      # Return the original string, just like MediaWiki does.
      return "[$url$anchor]";
    }
  }

  # Same procedure as for extracting URLs from brackets, except that we can't have an 
  # anchor in this case.

  sub collectStandaloneUrl($\%) {
    my ($url, $page) = @_;

    my @temp = split(/:/, $url, 2);
    my $urlProtocol = $temp[0];

    if( exists( $urlProtocols{$urlProtocol} ) ) {
      push(@{$page->{bareUrls}}, $url);
      push(@{$page->{externalLinks}}, { url => $url } );
      return "";
    } else {
      # Don't replace anything
      return "$url";
    }
  }
}

sub postprocessText(\$$$) {
  my ($refToText, $refToInterwikiArray) = @_;

  # Eliminate all <includeonly> and <onlyinclude> fragments, because this text
  # will not be included anywhere, as we already handled all inclusion directives
  # in function 'includeTemplates'.
  # This block can easily span several lines, hence the "/s" modifier.
  $$refToText =~ s/<includeonly>(?:.*?)<\/includeonly>/ /sg;
  $$refToText =~ s/<onlyinclude>(?:.*?)<\/onlyinclude>/ /sg;

  # <noinclude> fragments remain, but remove the tags per se
  # We block the code below, as <noinclude> tags will anyway be thrown away later,
  # when we eliminate all remaining tags.
  ### This block can easily span several lines, hence the "/s" modifier
  ### $$refToText =~ s/<noinclude>(.*?)<\/noinclude>/$1/sg;

  # replace <br> and <br /> directives with new paragraph
  $$refToText =~ s/<br(?:\s*)(?:[\/]?)>/\n\n/g;

  # Remove tables and math blocks, as they often carry a lot of noise
  &eliminateTables($refToText);
  &eliminateMath($refToText);

  # Since we limit the number of levels of template recursion, we might end up with several
  # un-instantiated templates. In this case we simply eliminate them now.
  # Because templates may be nested, we eliminate them iteratively by starting from the most
  # nested one (hence the 'while' loop).
  #    OLD comments and code:
  #    For the same reason, we also require that the body of a template does not contain
  #    opening braces (hence "[^\{]", any char except opening brace).
  #    1 while ($$refToText =~ s/\{\{(?:[^\{]*?)\}\}/ /sg);
  #    END OF old comments and code
  # We also require that the body of a template does not contain the template opening sequence
  # (two successive opening braces - "\{\{"). We use negative lookahead to achieve this.
  1 while ($$refToText =~ s/\{\{
                                 (?:
                                     (?:
                                         (?!
                                             \{\{
                                         )
                                         .
                                     )*?
                                 )
                            \}\}
                           / /sgx);

  # Remove any other <...> tags - but keep the text they enclose
  # (the tags are replaced with spaces to prevent adjacent pieces of text
  # from being glued together).
  $$refToText =~ s/<\/?[a-z][^<>]*?>/ /sg;

  # Change markup on bold/italics emphasis. We probably don't need to distinguish
  # these 3 types of emphasis, so we just replace all of them with a generic <em> tag.
  # IMPORTANT: If 'encodeXmlChars' has beeen called before this line, then remember that
  # the apostrophes were already quoted to "&apos;"
  $$refToText =~ s/'''''(.*?)'''''/$1/g;
  $$refToText =~ s/'''(.*?)'''/$1/g;
  $$refToText =~ s/''(.*?)''/$1/g;

  # Eliminate long sequences of newlines and whitespace.
  # Note that we don't want to replace sequences of spaces only, as this might make the text
  # less readable. Instead, we only eliminate sequences of whitespace that contain at least
  # two newlines.
  $$refToText =~ s/\s*\n\s*\n\s*/\n\n/g;

  # Eliminate XML entities such as "&nbsp;" , "&times;" etc. - otherwise,
  # in C++ code they will give rise to spurious words "nbsp", "times" etc.
  # Note that the standard entities - &amp; , &quot; , &apos; , &lt; and &gt;
  # are handled by the XML parser. All other entities, such as &nbsp; are passed
  # by the XML parser to the upper level (in case of Wikipedia pages,
  # to the rendering engine).
  # Note that in the raw XML text, these entities look like "&amp;nbsp;"
  # (i.e., with leading "&amp;"). XML parser replaces "&amp;" with "&",
  # so here in the code we see the entities as "&nbsp;".
  $$refToText =~ s{&                 # the entity starts with "&"
                   (\#?\w+)          # optional '#' sign (as in &#945;), followed by
                                     # an uninterrupted sequence of letters and/or digits
                   ;                 # the entity ends with a semicolon
                  }{ }gx;            # entities are replaced with a space

                                     # Replace with &logReplacedXmlEntity($1)
                                     # to log entity replacements.

  # NOTE that the following operations introduce XML tags, so they must appear
  # after the original text underwent character encoding with 'encodeXmlChars' !!
  
  # Convert magic words marking internal links to XML tags. Only properly nested 
  # tags are replaced.
  
  # We don't allow "==" to appear in links, since that could cause problems with
  # unbalanced <h1> and <internal> tags. There are very few legitimate links that
  # we ignore because of this.

  if( $refToInterwikiArray ) {
    
    # encode text for XML
    &encodeXmlChars($refToText);

    1 while( 
      $$refToText =~ s/\.pAriD=~(!?[0-9]+)~\.
                                                      (
                                                        (?:
                                                           (?!\.pAr)
                                                           (?!==)
                                                           .
                                                        )*?
                                                      )
                       \.pArenD\./&linkTag($1, $2, $refToInterwikiArray)/segx);
  }

  # Remove any unreplaced magic words. This replace also removes tags, that for some
  # reason aren't properly nested (and weren't caught by replace above).

  $$refToText =~ s/\.pAriD=~!?[0-9]+~\.//g;
  $$refToText =~ s/\.pArenD\.//g;

  # Change markup for section headers.
  # Note that section headers may only begin at the very first position in the line
  # (not even after a space). Therefore, each header markup in the following commands
  # is prefixed with "^" to make sure it begins at the beginning of the line.
  # Since the text (e.g., article body) may contains multiple lines, we use
  # the "/m" modifier to allow matching "^" at embedded "\n" positions.
  $$refToText =~ s/^=====(.*?)=====/<h4>$1<\/h4>/mg;
  $$refToText =~ s/^====(.*?)====/<h3>$1<\/h3>/mg;
  $$refToText =~ s/^===(.*?)===/<h2>$1<\/h2>/mg;
  $$refToText =~ s/^==(.*?)==/<h1>$1<\/h1>/mg;
}

sub linkTag {
  my ($id, $content, $refToInterwikiArray) = @_;

  if( $id =~ /^!([0-9]+)/ ) {
    my ($namespace, $title) = @{$refToInterwikiArray->[$1]};
    &encodeXmlChars(\$namespace);
    &encodeXmlChars(\$title);
    return "<link namespace=\"$namespace\" title=\"$title\">$content</link>";
  } else {
    return "<link id=\"$id\">$content</link>";
  }
}

sub logReplacedXmlEntity($) {
  my ($xmlEntity) = @_;

  LOG->debug("ENTITY: &$xmlEntity;");

  " "; # return value - entities are replaced with a space
}

BEGIN {
  my $mathSequence1 = qr/<math>(?:.*?)<\/math>/ixs;

  # Making variables static for the function to avoid recompilation of regular expressions
  # every time the function is called.

  # Table definitions can easily span several lines, hence the "/s" modifier

  # Examples where the eliminateTables() fails:
  #
  # 1) Table block opened with <table> and closed with |} or vice versa
  # 2) Table block opened and never closed because it is:
  #        a) The last thing on the page and the author didn't bother to close it
  #        b) Closed automatically by a === heading or some other markup

  my $tableOpeningSequence1 = qr{<table(?:                       # either just <table>
                                          (?:\s+)(?:[^<>]*)      # or
                                       )?>}ix;                   # "<table" followed by at least one space
                                                                 # (to prevent "<tablexxx"), followed by
                                                                 # some optional text, e.g., table parameters
                                                                 # as in "<table border=0>"

# Version above is more efficient
#
#  my $tableOpeningSequence1 = qr{<table>                         # either just <table>
#                                 |                               # or
#                                 <table(?:\s+)(?:[^<>]*)>}ix;    # "<table" followed by at least one space
#                                                                 # (to prevent "<tablexxx"), followed by
#                                                                 # some optional text, e.g., table parameters
#                                                                 # as in "<table border=0>"

                                 # In the above definition, prohibiting '<' and '>' chars ([^<>]) ensures
                                 # that we do not consume more than necessary, so that in the example
                                 #  "<table border=0> aaa <table> bbb </table> ccc </table>"
                                 #  $1 is NOT extended to be "> aaa <table"

  my $tableClosingSequence1 = qr/<\/table>/i;
#  my $nonNestedTableRegex1 =
#    qr{$tableOpeningSequence1            # opening sequence
#       (
#         (?:                             # non-capturing grouper
#             (?!                         # lookahead negation
#                 $tableOpeningSequence1  # that's what we don't want to find inside a table definition
#             )
#             .                           # any character (such that there is no table opening sequence
#                                         #   after it because of the lookahead condition)
#         )*?                             # shortest match of such characters, up to the closing of a table
#       )
#       $tableClosingSequence1}sx;        # closing sequence

  my $tableOpeningSequence2 = qr/\{\|/;
# We must take care that the closing sequence doesn't match any template parameters inside a table 
# (example " {{{footnotes|}}}). So we only match on a single closing brace.
  my $tableClosingSequence2 = qr/\|\}(?!\})/;
#  my $nonNestedTableRegex2 =
#    qr{$tableOpeningSequence2            # opening sequence
#       (
#         (?:                             # non-capturing grouper
#             (?!                         # lookahead negation
#                 $tableOpeningSequence2  # that's what we don't want to find inside a table definition
#             )
#             .                           # any character (such that there is no table opening sequence
#                                         #   after it because of the lookahead condition)
#         )*?                             # shortest match of such characters, up to the closing of a table
#       )
#       $tableClosingSequence2}sx;        # closing sequence

  my $tableSequence1 = qr/$tableOpeningSequence1(?:.*?)$tableClosingSequence1/s;
  my $tableSequence2 = qr/$tableOpeningSequence2(?:
                                                      (?:
                                                            (?!\{\|)          # Don't match nested tables
                                                            .
                                                      )*?
                                                )$tableClosingSequence2/sx;

  sub eliminateTables(\$) {
    my ($refToText) = @_;

    # Sometimes, tables are nested, therefore we use a while loop to eliminate them
    # recursively, while requiring that any table we eliminate does not contain nested tables.
    # For simplicity, we assume that tables of the two kinds (e.g., <table> ... </table> and {| ... |})
    # are not nested in one another.

    my $tableRecursionLevels = 0;

    $$refToText =~ s/$tableSequence1/\n/g;

    # We only resolve nesting {| ... |} style tables, which are often nested in infoboxes and similar
    # templates.

    while ( ($tableRecursionLevels < $Wikiprep::Config::maxTableRecursionLevels) &&
            $$refToText =~ s/$tableSequence2/\n/g ) {
    
      $tableRecursionLevels++;
    }
  }

  sub eliminateMath(\$) {
    my ($refToText) = @_;

    $$refToText =~ s/$mathSequence1/ /sg;
  }

} # end of BEGIN block

########################################################################

sub printUsage()
{
  print <<END
Wikiprep version $VERSION, Copyright (C) 2007 Evgeniy Gabrilovich

Wikiprep comes with ABSOLUTELY NO WARRANTY; for details type 
'$0 -license'.

This is free software, and you are welcome to redistribute it
under certain conditions; type '$0 -license' for details.

Type '$0 -version' for version information.

USAGE: $0 <options> -f <XML file with page dump>

 e.g.  $0 -f pages_articles.xml
   or  $0 -f pages_articles.xml.bz2

Available options:
  -pureperl      Use pure Perl implementation. This slows down
                 processing, but can be useful if Inline::C
                 isn't available. Note that the results of
                 template parsing with this option may differ in 
                 edge cases.
  -nourls        Don't extract external links (URLs) from pages. 
                 Reduces run-time by approximately one half.
  -log LEVEL     Set the amount of information to write to the log
                 file. With LEVEL set to "debug", the log can get
                 approximately 3-4 times larger than the XML dump.
  -compress      Enable compression on some of the output files.
  -lang LANG     Use language other than English. LANG is Wikipedia
                 language prefix (e.g. 'sl' for 'slwiki').
  -format FMT    Use output format FMT (default is legacy).

Available logging levels:

  debug, info, notice (default), warning, error

Output formats:

  legacy        Traditional output format, compatible with earliest
                versions of Wikiprep.
  composite     New format that consolidates most of the extracted
                data in a single large XML file.
END
}

&main;
