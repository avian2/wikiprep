# vim:sw=2:tabstop=2:expandtab

use strict;
use encoding 'utf-8';

package lang;

my $langDB = {

              # English
              # --------------------------------------------------------------------------------------------
              
              'en' => {
                  # Names of months as used by MediaWiki for date links
                  
                  'numberToMonth' => {
                      1 => 'January', 
                      2 => 'February', 
                      3 => 'March', 
                      4 => 'April',
                      5 => 'May', 
                      6 => 'June', 
                      7 => 'July', 
                      8 => 'August', 
                      9 => 'September', 
                      10 => 'October', 
                      11 => 'November', 
                      12 => 'December'
                  },
    
                  # Following three are pre-compiled regular expressions used for recognizing links to 
                  # related articles.
                  
                  # We require that stanalone designators occur at the beginning of the line
                  # (after at most a few characters, such as a whitespace or a colon),
                  # and not just anywhere in the line. Otherwise, we would collect as related
                  # those links that just happen to occur in the same line with an unrelated
                  # string that represents a standalone designator.
                  
                  'relatedWording_Standalone' =>
                      qr/Main(?:\s+)article(?:s?)|
                         Further(?:\s+)information|
                         Related(?:\s+)article(?:s?)|
                         Related(?:\s+)topic(?:s?)|
                         See(?:\s+)main(?:\s+)article(?:s?)|
                         See(?:\s+)article(?:s?)|
                         See(?:\s+)also|
                         For(?:\s+)(?:more|further)/ix,
                  ## For(?:\s+)more(?:\s+)(?:background|details)(?:\s+)on(?:\s+)this(?:\s+)topic,(?:\s+)see
                  
                  # Can appear anywhere in text, but must be enclosed in parentheses.

                  'relatedWording_Inline' =>
                      qr/See[\s:]|
                         See(?:\s+)also|
                         For(?:\s+)(?:more|further)/ix,

                  # Article sections containing links to related articles.

                  'relatedWording_Section' => 
                      qr/Further(?:\s+)information|
                         See(?:\s+)also|
                         Related(?:\s+)article(?:s?)|
                         Related(?:\s+)topic(?:s?)/ix,

                  # We only process pages in these namespaces + the main namespace (which has an empty name)

                  'okNamespacesForPrescanning' => {
                      'Template' => 1, 
                      'Category' => 1, 
                      'Image' => 1
                  },

                  # Pages in these namespaces end up in the final hgw.xml file.

                  'okNamespacesForTransforming' => {
                      'Category' => 1, 
                      'Image' => 1
                  },

                  # Pages in these namespaces that don't exist in the XML dump but have a link to it, 
                  # get assigned a local ID. Broken links to other pages get ignored.

                  'okNamespacesForLocalPages' => {
                      'Image' => 1
                  },

                  # Namespace for categories.

                  'categoryNamespace' =>
                      'Category',

                  # Namespace for templates.

                  'templateNamespace' =>
                      'Template',

                  # namespace for images.

                  'imageNamespace' =>
                      'Image',

                  # Regular expression that matches names of templates that mark disambiguation articles.

                  'disambigTemplates' =>
                      qr/disambiguation|
                         disambig|
                         dab|
                         hndis|
                         surname|
                         geodis|
                         schooldis|
                         hospitaldis|
                         mathdab|
                         numberdis/ix,

                  # Regular expression that matches titles of disambiguation articles.

                  'disambigTitle' =>
                      qr/\(disambiguation\)/ix,
              },

              # Slovene
              # --------------------------------------------------------------------------------------------

              'sl' => {
                  # Names of months as used by MediaWiki for date links
                  
                  'numberToMonth' => {
                      1 => 'Januuar', 
                      2 => 'Februar', 
                      3 => 'Marec', 
                      4 => 'April',
                      5 => 'Maj', 
                      6 => 'Junij', 
                      7 => 'Julij', 
                      8 => 'Avgust', 
                      9 => 'September', 
                      10 => 'Oktober', 
                      11 => 'November', 
                      12 => 'December'
                  },
    
                  # Following three are pre-compiled regular expressions used for recognizing links to 
                  # related articles.
                  
                  # We require that stanalone designators occur at the beginning of the line
                  # (after at most a few characters, such as a whitespace or a colon),
                  # and not just anywhere in the line. Otherwise, we would collect as related
                  # those links that just happen to occur in the same line with an unrelated
                  # string that represents a standalone designator.
                  
                  'relatedWording_Standalone' =>
                      qr/Glavni(?:\s+)član(ek|ki)|
                         Dodatne(?:\s+)informacije|
                         Povezani(?:\s+)član(ek|ki)|
                         Povezan(a|e)(?:\s+)tem(a|e)|
                         Glej(?:\s+)glavn(i|e)(?:\s+)član(ek|ke)|
                         Glej(?:\s+)član(ek|ke)|
                         Glej(?:\s+)tudi|
                         Za(?:\s+)(?:več|dodatn[io]|nadaljn[io])/ix,
                  ## For(?:\s+)more(?:\s+)(?:background|details)(?:\s+)on(?:\s+)this(?:\s+)topic,(?:\s+)see
                  
                  # Can appear anywhere in text, but must be enclosed in parentheses.

                  'relatedWording_Inline' =>
                      qr/Glej[\s:]|
                         Glej(?:\s+)tudi|
                         Za(?:\s+)(?:več|dodatn[io]|nadaljn[io])/ix,

                  # Article sections containing links to related articles.

                  'relatedWording_Section' => 
                      qr/Dodatne(?:\s+)informacije|
                         Glej(?:\s+)tudi|
                         Povezani?(?:\s+)član(ek|ki)|
                         Povezan[ea](?:\s+)tem[ea]/ix,

                  # We only process pages in these namespaces + the main namespace (which has an empty name)

                  'okNamespacesForPrescanning' => {
                      'Predloga' => 1, 
                      'Kategorija' => 1, 
                      'Slika' => 1
                  },

                  # Pages in these namespaces end up in the final hgw.xml file.

                  'okNamespacesForTransforming' => {
                      'Kategorija' => 1, 
                      'Slika' => 1
                  },

                  # Pages in these namespaces that don't exist in the XML dump but have a link to it, 
                  # get assigned a local ID. Broken links to other pages get ignored.

                  'okNamespacesForLocalPages' => {
                      'Slika' => 1
                  },

                  # Namespace for categories.

                  'categoryNamespace' =>
                      'Kategorija',

                  # Namespace for templates.

                  'templateNamespace' =>
                      'Predloga',

                  # namespace for images.

                  'imageNamespace' =>
                      'Slika',

                  # Regular expression that matches names of templates that mark disambiguation articles.

                  'disambigTemplates' =>
                      qr/razločitev/ix,

                  # Regular expression that matches titles of disambiguation articles.

                  'disambigTitle' =>
                      qr/\(razločitev\)/ix,
              }
          };

sub get($)
{
  my ( $langCode ) = @_;
  my $db = $langDB->{ $langCode };
    
  die("Invalid or unknown language code '$langCode'") unless ($db);

  return $db;
}

1
