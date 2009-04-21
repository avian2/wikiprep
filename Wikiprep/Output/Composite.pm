# vim:sw=2:tabstop=2:expandtab

package Wikiprep::Output::Composite;

use warnings;
use strict;

use Wikiprep::utils qw( encodeXmlChars getLinkIds removeDuplicatesAndSelf openOutputFile );

use XML::Writer;
use IO::File;

sub new {
	my $class = shift;

	my ($inputFile, %options) = @_;

  my $unsafe = not $options{DEBUG};
  my $self = {};

  if($options{PRESCAN}) {

    $self->{tmplFile} = openOutputFile($inputFile, ".tmpl.xml", %options, COMPRESS => 0);
    $self->{tmplWriter} = XML::Writer->new( OUTPUT => $self->{tmplFile}, 
                                            DATA_MODE => 1, 
                                            ENCODING => "utf-8",
                                            UNSAFE => $unsafe );
    $self->{tmplWriter}->xmlDecl();
    $self->{tmplWriter}->startTag("templates");

    $self->{redirFile} = openOutputFile($inputFile, ".redir.xml", %options, COMPRESS => 0);
    $self->{redirWriter} = XML::Writer->new(OUTPUT => $self->{redirFile}, 
                                            DATA_MODE => 1,
                                            ENCODING => "utf-8",
                                            UNSAFE => $unsafe );
  
    $self->{redirWriter}->xmlDecl();
    $self->{redirWriter}->startTag("redirects");

  } else {

    $self->{gumFile} = openOutputFile($inputFile, ".gum.xml", %options);
    $self->{gumWriter} = XML::Writer->new(OUTPUT => $self->{gumFile}, 
                                          DATA_MODE => 1, 
                                          ENCODING => "utf-8", 
                                          UNSAFE => $unsafe );
    $self->{gumWriter}->xmlDecl();
    $self->{gumWriter}->startTag("gum");

    $self->{disambigFile} = openOutputFile($inputFile, ".disambig", %options, COMPRESS => 0);

    print {$self->{disambigFile}} "# Line format: <Disambig page id>  ",
                                  "<Target page id (or \"undef\")> <Target anchor> ...\n\n\n";

    $self->{anchorFile} = openOutputFile($inputFile, ".anchor_text", %options);

    print {$self->{anchorFile}} "# Line format: <Target page id>  <Source page id>  ",
                                "<Anchor location within text>  ",
                                "<Anchor text (up to the end of the line)>\n\n\n";
  }

	bless $self, $class;

 	return $self;
}

sub finish {
  my $self = shift;

  while( my ($name, $value) = each(%$self) ) {
    if( $name =~ /Writer$/ ) {
      $value->endTag;
      $value->end;
    }
  }

  while( my ($name, $value) = each(%$self) ) {
    $value->close if( $name =~ /File$/ );
  }
}

# Save information about redirects into an XML-formatted file.
sub writeRedirects {
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

sub newTemplate {
  my $self = shift;
  my ($id, $title) = @_;

  my $writer = $self->{tmplWriter};

  $writer->startTag("template");
  $writer->dataElement("name", $title);
  $writer->dataElement("id", $id);
  $writer->endTag("template");
}

sub newPage {
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
