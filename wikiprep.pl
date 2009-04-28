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
use encoding 'utf8';

use File::Basename;
use File::Spec;

use Getopt::Long;
use Time::localtime;
use Parse::MediaWikiDump;
use Log::Handler wikiprep => 'LOG';
use BerkeleyDB;
use IO::Handle;
use IO::Select;
use Hash::Util qw( unlock_hash );

use FindBin;
use lib "$FindBin::Bin";

use Wikiprep::Config;
use Wikiprep::Link qw( %title2id %redir resolveLink parseRedirect extractWikiLinks );
use Wikiprep::Related qw( identifyRelatedArticles );
use Wikiprep::Disambig qw( isDisambiguation parseDisambig );
use Wikiprep::Namespace qw( loadNamespaces normalizeTitle isNamespaceOk %namespaces );
#use Wikiprep::Statistics qw( updateStatistics updateCategoryHierarchy 
#                             %statCategories %statIncomingLinks %catHierarchy );
use Wikiprep::images qw( convertGalleryToLink convertImagemapToLink );
use Wikiprep::revision qw( getWikiprepRevision getDumpDate getDatabaseName );
use Wikiprep::css qw( removeMetadata );
use Wikiprep::utils qw( encodeXmlChars removeDuplicatesAndSelf removeElements openInputFile );

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

my $optPrescan;
my $optTransform;

my $optParallel;

# Global constants
my $licenseFile = "COPYING";
my $VERSION = "3.0";

# Class that takes care of writing output files
my $outputClass;

# Input file
my $inputFilePath;
my $inputFileBase;
my $inputFileSuffix;

# Needed for benchmarking and ETA calculation
my $totalPageCount = 0;
my $totalByteCount = 0;

sub parseOptions {

  GetOptions('f=s'        => \$optFile,

             'license'    => \$optShowLicense,
             'version'    => \$optShowVersion,

             'nourls'     => \$optDontExtractUrls,
             'log=s'      => \$optLogLevel,
             'compress'   => \$optCompress,
             'config=s'   => \$optConfigName,
             'format=s'   => \$optOutputFormat,
             'pureperl=s' => \$optPurePerl,
             'prescan'    => \$optPrescan,
             'transform'  => \$optTransform,
             'parallel'   => \$optParallel);

  # Ignore any file part number. We find parts
  # to process automatically.
  $optFile =~ s/\.[0-9]+$//;

  if( not $optPrescan and not $optTransform ) {
    $optPrescan = 1;
    $optTransform = 1;
  }
}

sub loadModules {
  eval { Wikiprep::Config::init($optConfigName) };
  die "Can't load config $optConfigName: $@" if $@;

  $outputClass = sprintf("Wikiprep::Output::%s", ucfirst( lc( $optOutputFormat ) ) );

  my $outputModule = $outputClass;
  $outputModule =~ s/::/\//g;
  $outputModule .= ".pm";

  eval { require $outputModule };
  die "Can't load support for output format $optOutputFormat: $@" if $@;

  require Wikiprep::Templates; 
  use vars qw( %templates );
  Wikiprep::Templates->import qw( %templates includeTemplates );
}

sub getFilesToProcess {

  my @filesToProcess;

  if( -f "$optFile.0000" ) {
    my $n = 0;
    while(1) {
      my $filename = sprintf("%s.%04d", $optFile, $n);
      last unless -f $filename;

      push(@filesToProcess, [ $filename, $n ]);

      $n++;
    }
  } elsif( -f $optFile ) {
    push(@filesToProcess, [ $optFile, undef ] );
  }

  return @filesToProcess;
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

  ($inputFileBase, $inputFilePath, $inputFileSuffix) = fileparse($optFile, ".xml", ".xml.gz", ".xml.bz2");

  &loadModules;
  &initLog;

  my $startTime = time;

  if( $optPrescan ) {
    if( $optParallel ) {
      &mainPrescanParallel();
    } else {
      &mainPrescan();
    }
  }
  
  if( $optTransform ) {
    if( $optParallel ) {
      &mainTransformParallel();
    } else {
      &mainTransform();
    }
  }

  my $elapsed = time - $startTime;

  LOG->notice( sprintf("Processing took %d:%02d:%02d", $elapsed/3600, ($elapsed / 60) % 60, $elapsed % 60) );
}

sub mainPrescanParallel {

  if( my $pid = fork() ) {
    waitpid($pid, 0);
  } else {
    &mainPrescan();
    exit(0);
  }
}

sub mainPrescan
{
  my @filesToProcess = &getFilesToProcess();
  LOG->warning("No files to prescan") unless @filesToProcess;

  my $output = $outputClass->new($optFile, COMPRESS => $optCompress, PRESCAN => 1);

  my $count = 0;
  my $startTime = time;

  for my $el (@filesToProcess) {
    my ($inputFile, $part) = @$el;

    &prescan($inputFile, $output);

    $count++;

    my $elapsed = time - $startTime;
    if( $elapsed > 5 ) {
      my $filesPerSecond = $count / $elapsed;
      my $percentDone = $count * 100.0 / ($#filesToProcess + 1); 
      my $secondsLeft = ( $#filesToProcess + 1 - $count ) / $filesPerSecond;
      my $hoursLeft = $secondsLeft / 3600.0;
  
      printf "At %.1f%% ETA %.1f hours \r", $percentDone, $hoursLeft;
      STDOUT->flush();
    }
  }

  LOG->notice("total $totalPageCount pages ($totalByteCount bytes)");

  &Wikiprep::Link::prescanFinished();
  &Wikiprep::Templates::prescanFinished();

  $output->writeRedirects(\%redir, \%title2id, \%templates);

  $output->finish;

  &prescanSave();
}

sub mainTransform {

  my @filesToProcess = &getFilesToProcess();
  LOG->warning("No files to transform") unless @filesToProcess;

  &prescanLoad();
  open(F, "<", File::Spec->catfile($inputFilePath, $inputFileBase . ".count.db")) or die $!;
  my $totalByteCount = <F>;
  close(F);

  for my $el (@filesToProcess) {
    my ($inputFile, $part) = @$el;

    my $child_wtr;
    open($child_wtr, ">/dev/null");

    my $output = $outputClass->new($inputFile, COMPRESS => $optCompress, TRANSFORM => 1, PART => $part);
    &transform($inputFile, $output, $child_wtr);
    $output->finish;

    close $child_wtr;
  }
}

sub mainTransformParallel {
  my @filesToProcess = &getFilesToProcess();
  LOG->warning("No files to transform") unless @filesToProcess;

  my @pipes;
  my @workers;
  my $select = IO::Select->new;

  for my $el (@filesToProcess) {
    my ($inputFile, $part) = @$el;

    my $my_rdr = IO::Handle->new;
    my $child_wtr = IO::Handle->new;
    
    pipe $my_rdr, $child_wtr;

    if(my $pid = fork) {
      # parent
      close $child_wtr;
      push(@workers, $pid);
      $select->add($my_rdr);
    } else {
      #child
      close $my_rdr;
      &prescanLoad();
      my $output = $outputClass->new($inputFile, COMPRESS => $optCompress, TRANSFORM => 1, PART => $part);
      &transform($inputFile, $output, $child_wtr);
      $output->finish;
      close $child_wtr;
      exit(0);
    }
  }

  my $processedPageCount = 0;
  my $processedByteCount = 0;

  open(F, "<", File::Spec->catfile($inputFilePath, $inputFileBase . ".count.db")) or die $!;
  my $totalByteCount = <F>;
  close(F);

  my $startTime = time - 1;
  my $lastDisplayTime = $startTime;

  while($select->count) {
    my @rdr = $select->can_read;
    for my $rdr (@rdr) {
      my $status = <$rdr>;

      if($status eq "stop\n") {
        $select->remove($rdr);
        close $rdr;
      } else {
        $processedPageCount++;
        $processedByteCount += $status;
  
        if( time - $lastDisplayTime > 5 ) {
  
          $lastDisplayTime = time;
  
          my $bytesPerSecond = $processedByteCount / ( $lastDisplayTime - $startTime );
          my $percentDone = 100.0 * $processedByteCount / $totalByteCount;
          my $secondsLeft = ( $totalByteCount - $processedByteCount ) / $bytesPerSecond;
  
          my $hoursLeft = $secondsLeft / 3600.0;
  
          printf "At %.1f%% (%.0f bytes/s) ETA %.1f hours \r", $percentDone, $bytesPerSecond, $hoursLeft;
          STDOUT->flush();
        }
      }
    }
  }

  for my $pid (@workers) {
    waitpid($pid, 0);
  }

  print "\n";
}

# build id <-> title mappings and redirection table,
# as well as load templates
sub prescan {
  my ($inputFile, $output) = @_;
  my $fh = &openInputFile($inputFile);
  my $pages = Parse::MediaWikiDump::Pages->new( $fh );

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

    &Wikiprep::Templates::prescan(\$title, \$id, $mwpage, $output);
  }

  LOG->info("prescanning complete ($counter pages)");

  close($fh);
}

sub prescanSave {
  for my $name ("title2id", "redir", "templates", "namespaces") {
    my %db;
    my $filename = File::Spec->catfile($inputFilePath, $inputFileBase . ".$name.db");
    tie(%db, "BerkeleyDB::Hash", -Filename => $filename, -Flags => DB_TRUNCATE|DB_CREATE) or die $!;
    %db = eval("%" . $name);
    untie(%db);
  }
  open(F, ">", File::Spec->catfile($inputFilePath, $inputFileBase . ".count.db"));
  print F "$totalByteCount";
  close(F);
}

sub prescanLoad {
  for my $name ("title2id", "redir", "templates", "namespaces") {
    my $filename = File::Spec->catfile($inputFilePath, $inputFileBase . ".$name.db");
    my $db;
    eval('unlock_hash %' . $name);
    eval('%' . $name . ' = ()');
    eval('$db = tie(%' . $name . 
         ', "BerkeleyDB::Hash", -Filename => $filename, -Flags => DB_RDONLY) or die $!;');

    if( $name eq "templates" || $name eq "redir" ) {
      $db->filter_fetch_value( sub { $_ = Encode::decode('utf-8', $_) } );
    }
  }
}

sub transform {
  my ($inputFile, $output, $report) = @_;
  my $fh = &openInputFile($inputFile);
  my $mwpages = Parse::MediaWikiDump::Pages->new( $fh );

  while( my $mwpage = $mwpages->page ) {

    my $page = transformOne($mwpage);

    print $report $page->{orgLength}, "\n";
    $report->flush;

    next unless exists $page->{text};

    $output->newPage($page);
  }

  print $report "stop\n";
  $report->flush;

  close($fh);
}

sub transformOne {
  my ($mwpage) = @_;

  my $categoryNamespace = $Wikiprep::Config::categoryNamespace;
  my $imageNamespace = $Wikiprep::Config::imageNamespace;

  my $page = {};

  $page->{startTime} = time;

  my $text = ${$mwpage->text};

  $page->{id} = $mwpage->id;
  # text length BEFORE any transformations
  $page->{orgLength} = length($text);

  LOG->debug("transforming page (ID $page->{id})");

  if( defined( &parseRedirect($mwpage) ) ) {
    # we've already loaded all redirects in the prescanning phase
    return $page;
  }

  if( ! &isNamespaceOk( $mwpage->namespace, \%Wikiprep::Config::okNamespacesForTransforming) ) {
    return $page; # we're only interested in pages from certain namespaces
  }

  my $title = $mwpage->title;
  &normalizeTitle(\$title);

  # see the comment about empty titles in function 'prescan'
  if (length($title) == 0) {
    LOG->debug("skipping page with empty title (ID $page->{id})");
    return $page;
  }

  $page->{title} = $title;
  $page->{timestamp} = $mwpage->timestamp;

  # next if( $id != 1192748);

  # Remove comments (<!-- ... -->) from text. This is best done as early as possible so
  # that it doesn't slow down the rest of the code.
      
  # Comments can easily span several lines, so we use the "/s" modifier.

  $text =~ s/<!--.*?-->//sg;

  # Enable this to parse Uncyclopedia (<choose> ... </choose> is a
  # MediaWiki extension they use that selects random text - wikiprep
  # creates huge pages if we don't remove it)

  # $text =~ s/<choose[^>]*>(?:.*?)<\/choose[^>]*>/ /sg;

  # The check for stub must be done BEFORE any further processing,
  # because stubs indicators are templates, and templates are substituted.
  if ( $text =~ /stub\}\}/i ) {
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
  &includeTemplates($page, \$page->{text}, 0);

  # This function only examines the contents of '$text', but doesn't change it.
  &identifyRelatedArticles($page);

  &convertGalleryToLink(\$page->{text});
  &convertImagemapToLink(\$page->{text});

  # Remove <div class="metadata"> ... </div> and similar CSS classes that do not
  # contain usable text for us.
  &removeMetadata(\$page->{text});

  $page->{internalLinks} = [];
  $page->{categories} = [];
  $page->{interwiki} = [];

  &extractWikiLinks(\$page->{text}, $page->{internalLinks}, $page->{interwiki}, $page->{categories});
    
  # Categories are listed at the end of articles, and therefore may mistakenly
  # be added to the list of related articles (which often appear in the last
  # section such as "See also"). To avoid this, we explicitly remove all categories
  # from the list of related links, and only then record the list of related links
  # to the file.
  &removeElements($page->{relatedArticles}, $page->{categories});

  # We don't accumulate categories directly in a hash table, since this would not preserve
  # their original order of appearance.
  &removeDuplicatesAndSelf($page->{categories}, $page->{id});

  if ( ! $optDontExtractUrls ) {
    &extractUrls($page);
  }

  &postprocessText(\$page->{text}, $page->{interwiki});

  # text length AFTER all transformations
  $page->{newLength} = length($page->{text});

  if( $mwpage->namespace eq $categoryNamespace ) {
    $page->{isCategory} = 1;
  } else {
    $page->{isCategory} = 0;
  }

  $page->{isImage} = $mwpage->namespace eq $imageNamespace ? 1 : 0;

  my $pageFinishedTime = time;

  LOG->info( sprintf("transforming page took %d seconds (ID %d)", $pageFinishedTime - $page->{startTime}, 
             $page->{id}) );

  return $page;
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
    return "<w namespace=\"$namespace\" title=\"$title\">$content</w>";
  } else {
    return "<a id=\"$id\">$content</a>";
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
                                          \s+[^<>]*              # or
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
  -prescan       Prescan the dump.
  -transform     Transform the dump.
                 (default is to both prescan and transform).
  -parallel      Run in multiple, parallel processes. (see 
                 documentation)

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
