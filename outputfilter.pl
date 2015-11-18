#!/usr/bin/perl

use strict;
use warnings;

use DBI;
use FindBin qw($Bin);
use Text::Xslate;
use POSIX qw(strftime);
use List::MoreUtils qw(uniq);
use Getopt::Long;
use YAML::XS qw(LoadFile);
use Net::LDAP;
use Data::Dumper;

# LDAP related constants, we can pull these details from a config file
use constant LDAP_SERVER => 'directory';
use constant LDAP_BASEDN => 'o=Organisation, c=AU';

my $createfile = '';
my $yamlfile = '';
my $outputfile = '';

GetOptions
(
    'c|create=s' => \$createfile,
    'y|yaml=s'   => \$yamlfile, 
    'o|out=s'    => \$outputfile,
);

die "Must specify -y|--yaml [filename] or -c|--create [filename]\n" if !$yamlfile && !$createfile;

sub set_time
{
  my ($filter) = @_;

  $filter->{timeNow} = time;
  $filter->{timeStamp} = strftime("%FT%TZ", localtime);
}

sub apply_template
{
  my ($output_filters, $template, $values) = @_;

  die "Unknown template specified $!\n" if !defined $template;

  foreach my $val (@$values)
  {
    my %properties = %$template;
    my %filter = ( properties => \%properties );
    while (my ($key, $template_value) = each %$template)
    {
      $properties{$key} = sprintf($template_value, $val);
    }
    set_time(\%filter);
    push(@$output_filters, \%filter);
  }
}

sub read_yaml
{
  my ($yaml) = @_;

  my $filter_input = LoadFile($yaml);

  my %filter_output = (
    engineerName  => $filter_input->{engineerName},
    engineerEmail => $filter_input->{engineerEmail},
    filters       => [],
  );

  foreach my $filter (@{$filter_input->{filters}})
  {
    # skip disabled filters, enabled by default
    next if exists $filter->{enabled} && (!$filter->{enabled} || lc($filter->{enabled}) eq 'false');
    
    if (exists $filter->{useTemplate})
    {
      apply_template($filter_output{filters}, $filter_input->{templates}{$filter->{useTemplate}}, $filter->{values});
    }
    else
    {
      my %output = ( properties => $filter );
      set_time(\%output);
      push(@{$filter_output{filters}}, \%output);
    }
  }

  return \%filter_output;
}

sub get_hosts
{
  my ($username, $primary) = @_;

  # pull these details also from config file
  my $dbname = '';
  my $dbhost = '';
  my $dbh = DBI->connect("DBI:Pg:dbname=$dbname;host=$dbhost", "view", " ", {'RaiseError' => 1});

  my $sth = $dbh->prepare("SELECT hostname,nearphone FROM addhost WHERE nearphone LIKE '%" . $username . "%'");
  $sth->execute();

  my @hosts;
  while (my $ref = $sth->fetchrow_hashref()) 
  {
    # skip decom records
    next if $ref->{'nearphone'} =~ /:Dec:/i;

    my $hostname = $ref->{'hostname'};
    # strip out .null if it exists
    $hostname =~ s/\.null//;

    if (exists $ref->{'nearphone'} && defined $ref->{'nearphone'})
    {
      my @nearphone = split(/:/, $ref->{'nearphone'});
      my @admins = uniq split(/\+/, $nearphone[2]);
      if (lc($primary) eq 'p' && $admins[0] eq $username || lc($primary) eq 'a')
      {
        push(@hosts, $hostname);  
      }
    }
  }

  print "Found " . scalar @hosts . " servers\n";

  return \@hosts;
}

sub get_user_details
{
  my ($username) = @_;

  my $ldap = Net::LDAP->new(LDAP_SERVER) or die "$@";
  $ldap->bind;

  my $attrs = [ 'cn', 'mail' ];
  my $results = $ldap->search(base => LDAP_BASEDN, attrs => $attrs, filter => "(uid=$username)");
  $results->code && die $results->error;

  die "Unable to find uid=$username in LDAP" if scalar $results->entries == 0; 
  die "Unexpected multiple results: " . Dumper($results->entries) if scalar $results->entries > 1;

  my @ldap_entry = $results->entries;
  my $name = $ldap_entry[0]->get_value('cn');
  my $email = $ldap_entry[0]->get_value('mail');

  print "\nSetting engineerName: " . $name . "\n";
  print "Setting engineerEmail: " . $email . "\n";

  $ldap->unbind;

  return ($name, $email);
}

if ($yamlfile)
{
  my $filter_output = read_yaml($yamlfile);
  set_time($filter_output);

  my $xslate = Text::Xslate->new(path => ["$Bin/templates"]);
  my $content = $xslate->render("filter.tx", $filter_output);

  if ($outputfile)
  {
    open my $out, ">", $outputfile or die "Unable to open $outputfile: $!";
    print $out $content;
    close $out;
  }
  else
  {
    print $content;
  }
}
elsif ($createfile)
{
  print "A couple questions are needed to generate the definition file. Press Ctrl+C to cancel.\n\n";

  print "Authcate username: ";
  my $username = <>;
  chomp $username;

  print "Primary admin or Any admin systems [p|a]: ";
  my $primary = <>;
  chomp $primary;

  die "Unknown option: $primary" if $primary !~ /p|a/i;

  my ($name, $email) = get_user_details($username);
  my $servers = get_hosts($username, $primary);

  # verify username and get the systems requested
  my %definition_output = (
    engineerName  => $name,
    engineerEmail => $email,
    servers       => $servers,
  );

  my $xslate = Text::Xslate->new(path => ["$Bin/templates"]);
  my $content = $xslate->render("definition.tx", \%definition_output);

  print "Writing definition file out to $createfile\n";
  open my $out, ">", $createfile or die "Unable to open $createfile: $!";
  print $out $content;
  close $out;
  print "Done.\n";
}
