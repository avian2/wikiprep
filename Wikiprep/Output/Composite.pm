# vim:sw=2:tabstop=2:expandtab

package Wikiprep::Output::Composite;

use warnings;
use strict;

use Wikiprep::utils qw( encodeXmlChars getLinkIds removeDuplicatesAndSelf );

use XML::Writer;
use IO::File;

sub new 
{
	my $class = shift;

	my $basepath = shift;
  my $inputFile = shift;
  my %params = @_;

  my $unsafe = not $params{DEBUG};

  my $gumFile;
  if( $params{COMPRESS} ) {
    $gumFile = IO::File->new("| gzip >$basepath.gum.xml.gz");
  } else {
    $gumFile = IO::File->new("> $basepath.gum.xml");
  }
  my $gumWriter = XML::Writer->new(OUTPUT => $gumFile, DATA_MODE => 1, ENCODING => "utf-8", 
                                                                       UNSAFE => $unsafe );
  $gumWriter->xmlDecl();
  $gumWriter->startTag("gum");

  my $interwikiFile = IO::File->new("> $basepath.interwiki.xml");
  my $interwikiWriter = XML::Writer->new(OUTPUT => $interwikiFile, DATA_MODE => 1, ENCODING => "utf-8",
                                                                           UNSAFE => $unsafe );
  $interwikiWriter->xmlDecl();
  $interwikiWriter->startTag("pages");

  my $redirFile = IO::File->new("> $basepath.redir.xml");
  my $redirWriter = XML::Writer->new(OUTPUT => $redirFile, DATA_MODE => 1, ENCODING => "utf-8",
                                                                           UNSAFE => $unsafe );
  $redirWriter->xmlDecl();
  $redirWriter->startTag("redirects");

  my $tmplFile = IO::File->new("> $basepath.tmpl.xml");
  my $tmplWriter = XML::Writer->new(OUTPUT => $tmplFile, DATA_MODE => 1, ENCODING => "utf-8",
                                                                         UNSAFE => $unsafe );
  $tmplWriter->xmlDecl();
  $tmplWriter->startTag("templates");

  my $self = { 
                gumFile    => $gumFile,
                gumWriter  => $gumWriter,

                interwikiFile    => $interwikiFile,
                interwikiWriter  => $interwikiWriter,

                redirFile    => $redirFile,
                redirWriter  => $redirWriter,

                tmplFile    => $tmplFile,
                tmplWriter  => $tmplWriter,
             };

  my $disambigFile = "$basepath.disambig";
  open( $self->{disambigFile}, "> $disambigFile") or 
    die "Cannot open $disambigFile: $!";
  binmode($self->{disambigFile}, ':utf8');

  print {$self->{disambigFile}} "# Line format: <Disambig page id>  ",
                                "<Target page id (or \"undef\")> <Target anchor> ...\n\n\n";

  my $anchorFile = "$basepath.anchor_text";
  if( $params{COMPRESS} ) {
    open( $self->{anchorFile}, "| gzip >$anchorFile.gz") or 
      die "Cannot open to gzip: $anchorFile.gz: $!";
  } else {
    open( $self->{anchorFile}, "> $anchorFile") or 
      die "Cannot open $anchorFile.gz: $!";
  }
  binmode($self->{anchorFile}, ':utf8');

  print {$self->{anchorFile}} "# Line format: <Target page id>  <Source page id>  ",
                              "<Anchor location within text>  ",
                              "<Anchor text (up to the end of the line)>\n\n\n";

  my $statCategoriesFile = "$basepath.stat.categories";
  open( $self->{statCategoriesFile}, "> $statCategoriesFile") or
    die "Cannot open $statCategoriesFile: $!";

  print {$self->{statCategoriesFile}} 
                  "# Line format: <CategoryId (= page id)>  <Number of pages in this category>\n",
                  "# Here we count the *pages* that belong to this category, i.e., articles AND\n",
                  "# sub-categories of this category (but not the articles in the sub-categories).\n",
                  "\n\n";

  my $statInlinksFile = "$basepath.stat.inlinks";
  open( $self->{statInlinksFile}, "> $statInlinksFile") or
    die "Cannot open $statInlinksFile: $!";

  print {$self->{statInlinksFile}} 
                  "# Line format: <Target page id>  <Number of links to it from other pages>\n\n\n";

  my $catHierarchyFile = "$basepath.stat.inlinks";
  open( $self->{catHierarchyFile}, "> $catHierarchyFile") or
    die "Cannot open $catHierarchyFile: $!";

  print {$self->{catHierarchyFile}} 
                  "# Line format: <Category id>  <List of ids of immediate descendants>\n\n\n";

	bless $self, $class;

	return $self;
}

sub finish
{
  my $self = shift;

  $self->{gumWriter}->endTag();
  $self->{gumWriter}->end();
  $self->{gumFile}->close();

  $self->{interwikiWriter}->endTag();
  $self->{interwikiWriter}->end();
  $self->{interwikiFile}->close();

  $self->{redirWriter}->endTag();
  $self->{redirWriter}->end();
  $self->{redirFile}->close();

  $self->{tmplWriter}->endTag();
  $self->{tmplWriter}->end();
  $self->{tmplFile}->close();

  close( $self->{disambigFile} );
  close( $self->{anchorFile} );

  close( $self->{statCategoriesFile} );
  close( $self->{statInlinksFile} );
  close( $self->{catHierarchyFile} );
}

# Save information about redirects into an XML-formatted file.
sub writeRedirects 
{
  my $self = shift;
  my ($refToRedir, $refToTitle2Id, $refToTemplates) = @_;

  my $writer = $self->{redirWriter};

  while(my ($fromTitle, $toTitle) = each(%$refToRedir)) {

    my $fromId;
    if( exists $refToTitle2Id->{$fromTitle} ) {
      $fromId = $refToTitle2Id->{$fromTitle} 
    } else {
      $fromId = "unknown";
    }

    my $toId;
    if( exists $refToTitle2Id->{$toTitle} ) {
      $toId = $refToTitle2Id->{$toTitle} 
    } else {
      $toId = "unknown";
    }

    if( exists( $refToTemplates->{$fromId} ) ) {
      next;
    } elsif( exists( $refToTemplates->{$toId} ) ) {
      $self->{tmplWriter}->startTag("template");
      $self->{tmplWriter}->dataElement("name", $fromTitle);
      $self->{tmplWriter}->dataElement("id", $toId);
      $self->{tmplWriter}->endTag("template");
    } else {
      $writer->startTag("redirect");
      $writer->startTag("from");
      $writer->dataElement("id", $fromId);
      $writer->dataElement("name", $fromTitle);
      $writer->endTag("from");
      $writer->startTag("to");
      $writer->dataElement("id", $toId);
      $writer->dataElement("name", $toTitle);
      $writer->endTag("to");
      $writer->endTag("redirect");
    }
  }
}

sub newTemplate 
{
  my $self = shift;
  my ($id, $title) = @_;

  my $writer = $self->{tmplWriter};

  $writer->startTag("template");
  $writer->dataElement("name", $title);
  $writer->dataElement("id", $id);
  $writer->endTag("template");
}

sub newPage 
{
  my $self = shift;
  my ($page) = @_;

  my @internalLinks;
  &getLinkIds(\@internalLinks, $page->{internalLinks});
  &removeDuplicatesAndSelf(\@internalLinks, $page->{id});

  my $writer = $self->{gumWriter};

  $writer->startTag("page", id          => $page->{id},
                            timestamp   => $page->{timestamp} || '',
                            orglength   => $page->{orgLength},
                            newlength   => $page->{newLength},
                            stub        => $page->{isStub},
                            disambig    => $page->{isDisambig},
                            category    => $page->{isCategory},
                            image       => $page->{isImage} );

  $writer->dataElement("title", $page->{title});

  $writer->dataElement("categories", join(" ", @{$page->{categories}}));

  $writer->dataElement("links", join(" ", @internalLinks));

  $writer->dataElement("related", join(" ", @{$page->{relatedArticles}}));

  $writer->startTag("external");
  for my $link (@{$page->{externalLinks}}) {
    if( $link->{anchor} ) {
      $writer->dataElement("link", $link->{anchor}, url => $link->{url});
    } else {
      $writer->emptyTag("link", url => $link->{url});
    }
  }
  $writer->endTag("external");

  $writer->startTag("interwiki");
  for my $link (@{$page->{interwikiLinks}}) {
      $writer->emptyTag("link", wiki  => $link->{targetWiki},
                                title => $link->{targetTitle} );
  }
  $writer->endTag("interwiki");

  $writer->startTag("templates");
  while(my ($templateId, $log) = each(%{$page->{templates}})) {
    $writer->startTag("template", id => $templateId);
    for my $refToParameterHash (@$log) {
      $writer->startTag("include");
      while( my ($parameter, $value) = each(%$refToParameterHash) ) {
        if($parameter !~ /^=/) {
          $writer->dataElement("parameter", $value, name => $parameter)
        }
      }
      $writer->endTag("include");
    }
    $writer->endTag("template");
  }
  $writer->endTag("templates");

  print {$self->{gumFile}} "<text>", $page->{text}, "</text>";

  $writer->endTag("page");

  $self->_logDisambig($page);
  $self->_logAnchorText($page);
}

sub writeStatistics {
  my $self = shift;
  my ($refToStatCategories, $refToStatIncomingLinks) = @_;

  for my $cat ( keys(%$refToStatCategories) ) {
    print {$self->{statCategoriesFile}} "$cat\t$refToStatCategories->{$cat}\n";
  }

  for my $destination ( keys(%$refToStatIncomingLinks) ) {
    print {$self->{statInlinksFile}} "$destination\t$refToStatIncomingLinks->{$destination}\n";
  }
}

sub writeCategoryHierarchy {
  my $self = shift;
  my ($refCatHierarchy) = @_;

  for my $cat ( keys(%$refCatHierarchy) ) {
    print {$self->{catHierarchyFile}} "$cat\t", join(" ", @{$refCatHierarchy->{$cat}}), "\n";
  }
}

sub writeInterwiki
{
  my $self = shift;
  my ($refToInterwiki) = @_;

  my $writer = $self->{interwikiWriter};

  while( my( $namespace, $titleArray ) = each( %$refToInterwiki ) ) {

    $writer->startTag("namespace", name => $namespace);

    for my $title (@$titleArray) {
      $writer->emptyTag("page", title => $title);
    }

    $writer->endTag("namespace");
  }
}

sub _logDisambig 
{
  my $self = shift;
	my ($page) = @_;

  return unless $page->{isDisambig};

  my $file = $self->{disambigFile};

  for my $disambigLinks (@{$page->{disambigLinks}}) {

	  print $file $page->{id};

    for my $anchor (@$disambigLinks) {
      if( defined( $anchor->{'targetId'} ) ) {
        print $file "\t$anchor->{'targetId'}";
      } else {
        print $file "\tundef";
      }
      my $anchorText = $anchor->{'anchorText'};
      $anchorText =~ s/\t/ /g;
      print $file "\t$anchorText";
    }

  	print $file "\n";
  }
}

sub _logAnchorText 
{
  my $self = shift;
  my ($page) = @_;

  # We remove the links that point from the page to itself.
  foreach my $AnchorArrayEntry (@{$page->{internalLinks}}) {
    my $targetId = $AnchorArrayEntry->{targetId};
    my $anchorText = $AnchorArrayEntry->{anchorText};
    my $linkLocation = $AnchorArrayEntry->{linkLocation};

    if (defined($targetId) and $targetId != $page->{id}) {
      $anchorText =~ s/\n/ /g;  # replace all newlines with spaces

      $anchorText =~ s/^\s*//g;  # remove leading and trainling whitespace
      $anchorText =~ s/\s*$//g;

      print {$self->{anchorFile}} "$targetId\t$page->{id}\t$linkLocation\t$anchorText\n";
    }
  }
}

1;
