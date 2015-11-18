# Gmail filter definition in YAML

## What is this?

While in the process of cleaning up monitoring alerts I thought it would be useful to be able to:
-  Version control my filters easily in a format less verbose than XML
-  Create new filters easily based on templates to reuse definitions
-  Generate filters automatically for the servers I look after
-  Have the ability to share filters between colleagues
-  Document filters in the YAML file

## How to use

1.  Firstly create a filter template. An example is in templates/definition.tx.
2.  Run outputfilter.pl -c _filename_ to generate a new populated YAML file named filename for filter creation from the template.
3.  Lastly outputfilter.pl -y _filename_ will read the specified YAML file and output the Gmail filters to be imported.

Also demonstrated is a PoC self-service web site to generate filters written in Ruby using the Sinatra web framework.
