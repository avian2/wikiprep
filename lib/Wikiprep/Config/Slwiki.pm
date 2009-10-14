# vim:sw=2:tabstop=2:expandtab

use encoding 'utf-8';

# Slovene Wikipedia
# --------------------------------------------------------------------------------------------

# Names of months as used by MediaWiki for date links
%numberToMonth = (
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
                  );

$namespaceAliases = ();

# Following three are pre-compiled regular expressions used for recognizing links to 
# related articles.

# We require that stanalone designators occur at the beginning of the line
# (after at most a few characters, such as a whitespace or a colon),
# and not just anywhere in the line. Otherwise, we would collect as related
# those links that just happen to occur in the same line with an unrelated
# string that represents a standalone designator.

$relatedWording_Standalone = qr/Glavni(?:\s+)član(ek|ki)|
                                Dodatne(?:\s+)informacije|
                                Povezani(?:\s+)član(ek|ki)|
                                Povezan(a|e)(?:\s+)tem(a|e)|
                                Glej(?:\s+)glavn(i|e)(?:\s+)član(ek|ke)|
                                Glej(?:\s+)član(ek|ke)|
                                Glej(?:\s+)tudi|
                                Za(?:\s+)(?:več|dodatn[io]|nadaljn[io])/ix;

# Can appear anywhere in text, but must be enclosed in parentheses.

$relatedWording_Inline = qr/Glej[\s:]|
                            Glej(?:\s+)tudi|
                            Za(?:\s+)(?:več|dodatn[io]|nadaljn[io])/ix;

# Article sections containing links to related articles.

$relatedWording_Section = qr/Dodatne(?:\s+)informacije|
                             Glej(?:\s+)tudi|
                             Povezani?(?:\s+)član(ek|ki)|
                             Povezan[ea](?:\s+)tem[ea]/ix;

# We only process pages in these namespaces + the main namespace (which has an empty name)

%okNamespacesForPrescanning = (
                                'Predloga' => 1, 
                                'Kategorija' => 1, 
                                'Slika' => 1 
                              );

# Pages in these namespaces end up in the final hgw.xml file.

%okNamespacesForTransforming = (
                                'Kategorija' => 1, 
                                'Slika' => 1
                              );

# Pages in these namespaces that don't exist in the XML dump but have a link to it, 
# get assigned a local ID. Broken links to other pages get ignored.

%okNamespacesForLocalPages = (
                                'Slika' => 1
                              );

# Namespace for categories.

$categoryNamespace = 'Kategorija';

# Namespace for templates.

$templateNamespace = 'Predloga';

# namespace for images.

$imageNamespace = 'Slika';

# Regular expression that matches names of templates that mark disambiguation articles.

$disambigTemplates = qr/razločitev|
                        razločitveni|
                        disambig|
                        dab/ix;

# Regular expression that matches titles of disambiguation articles.

$disambigTitle = qr/\(razločitev\)/ix;

1;
