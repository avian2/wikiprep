# vim:sw=2:tabstop=2:expandtab

require Wikiprep::Config::Enwiki;

# Wikinvest
# --------------------------------------------------------------------------------------------
              
# Aliases for namespaces. Link [[Image:X]] is identical to [[File:X]]. XML dump file
# contains only pages in the File: namespace.

%namespaceAliases = ( );
    
# We only process pages in these namespaces + the main namespace (which has an empty name)

%okNamespacesForPrescanning = (
                      	'Template' => 1, 

                        'Stock' => 1, 
                        'Metric' => 1,
                        'Concept' => 1,
                        'Industry' => 1
                    );

# Pages in these namespaces end up in the final hgw.xml file.

%okNamespacesForTransforming = (
                        'Stock' => 1, 
                        'Metric' => 1,
                        'Concept' => 1,
                        'Industry' => 1
                    ); 

# Pages in these namespaces that don't exist in the XML dump but have a link to it, 
# get assigned a local ID. Broken links to other pages get ignored.

%okNamespacesForLocalPages = (
                      'Image' => 1
                    );

# Namespace for categories.

$categoryNamespace = 'Category';

# Namespace for templates.

$templateNamespace = 'Template';

# namespace for images.

$imageNamespace = 'Image';

1;
