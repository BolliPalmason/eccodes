#!/usr/bin/env perl
#
# (C) Copyright 2005- ECMWF.
#
# This software is licensed under the terms of the Apache Licence Version 2.0
# which can be obtained at http://www.apache.org/licenses/LICENSE-2.0.
#
# In applying this licence, ECMWF does not waive the privileges and immunities
# granted to it by virtue of its status as an intergovernmental organisation
# nor does it submit to any jurisdiction.
#
#######################################################################
# Script to generate parameter definition files for GRIB2.
# Reads an input TSV (tab-separated-value) file which should contain
# the following parameter keys as columns:
#   paramId
#   shortName
#   name
#   units
#   discipline
#   parameterCategory
#   parameterNumber
#   # The following are optional keys
#   typeOfFirstFixedSurface
#   scaleFactorOfFirstFixedSurface
#   scaledValueOfFirstFixedSurface
#   typeOfSecondFixedSurface
#   scaleFactorOfSecondFixedSurface
#   scaledValueOfSecondFixedSurface
#   typeOfStatisticalProcessing
#
# It outputs the def files:
#    name.def paramId.def shortName.def units.def cfVarName.def
#
#######################################################################
$|=1;
use strict;
use warnings;
use DBI;
use Time::localtime;

$ARGV[0] or die "USAGE: $0 input.tsv\n";

my $WRITE_TO_FILES = 0;
my $WRITE_TO_PARAMDB = 0;

my ($paramId, $shortName, $name, $units, $cfVarName);
my ($discipline, $pcategory, $pnumber, $type1, $type2, $scaledValue1, $scaleFactor1, $scaledValue2, $scaleFactor2, $stat);

my %key_to_attrib_map = (
    'discipline'         => 4,
    'parameterCategory'  => 8,
    'parameterNumber'    => 5,
    'localTablesVersion' => 16,
    'typeOfFirstFixedSurface' => 6,
    'scaleFactorOfFirstFixedSurface' => 7,
    'scaledValueOfFirstFixedSurface' => 9,
    'typeOfStatisticalProcessing' => 11,
    'typeOfSecondFixedSurface' => 13,
    'scaledValueOfSecondFixedSurface' => 14,
    'scaleFactorOfSecondFixedSurface' => 15,
    'typeOfGeneratingProcess' => 28,
    'constituentType' => 40,
    'aerosolType' => 46
);
my $db = "param";
my $host = $ENV{'DB_HOST'} || 'unknown';
my $user = $ENV{'DB_USER'} || 'unknown';
my $pass = $ENV{'DB_PASS'} || 'unknown';
my $dbh = 0;
my $centre = -3; # WMO
my $edition = 2;
my $contactId = "A test"; # JIRA issue ID

my $PARAMID_FILENAME   = "paramId.def";
my $SHORTNAME_FILENAME = "shortName.def";
my $NAME_FILENAME      = "name.def";
my $UNITS_FILENAME     = "units.def";
my $CFVARNAME_FILENAME = "cfVarName.def";

my $tm = localtime;
my $today_date = sprintf("%04d-%02d-%02d", $tm->year+1900, ($tm->mon)+1, $tm->mday);
print "Using insert and update dates: $today_date\n";

if ($WRITE_TO_FILES) {
    create_or_append(\*OUT_PARAMID,   "$PARAMID_FILENAME");
    create_or_append(\*OUT_SHORTNAME, "$SHORTNAME_FILENAME");
    create_or_append(\*OUT_NAME,      "$NAME_FILENAME");
    create_or_append(\*OUT_UNITS,     "$UNITS_FILENAME");
    create_or_append(\*OUT_CFVARNAME, "$CFVARNAME_FILENAME");
}
if ($WRITE_TO_PARAMDB) {
    $dbh = DBI->connect("dbi:mysql(RaiseError=>1):database=$db;host=$host",$user,$pass) or die $DBI::errstr;
}

my $first = 1;
while (<>) {
    chomp;
    s/\r//g;  # Remove DOS carriage returns
    if ($first == 1) {
        check_first_row_column_names($_);
        $first = 0;
        next;
    }

    ($paramId, $shortName, $name, $units,
        $discipline, $pcategory, $pnumber, $type1, $type2,
        $scaledValue1, $scaleFactor1, $scaledValue2, $scaleFactor2, $stat) = split(/\t/);

    die "Error: paramID \"$paramId\" is not an integer!" if (!is_integer($paramId));

    $units = "~" if ($units eq "");
    $cfVarName = $shortName;
    $cfVarName = '\\'.$shortName if ($shortName =~ /^[0-9]/);

    if ($WRITE_TO_FILES) {
        write_out_file(\*OUT_PARAMID,   $name, $paramId);
        write_out_file(\*OUT_SHORTNAME, $name, $shortName);
        write_out_file(\*OUT_NAME,      $name, $name);
        write_out_file(\*OUT_UNITS,     $name, $units);
        write_out_file(\*OUT_CFVARNAME, $name, $cfVarName);
    }

    if ($WRITE_TO_PARAMDB) {
        my $units_code = get_db_units_code($units);
        my $is_chem = "y";
        my $is_aero = "y";
        $dbh->do("insert into param(id,shortName,name,units_id,insert_date,update_date,contact) values (?,?,?,?,?,?,?)",undef,
            $paramId, $shortName, $name , $units_code, $today_date, $today_date, $contactId);

      # Table 'grib' columns: param_id  edition  centre  attribute_id  attribute_value  param_version
      $dbh->do("insert into grib values (?,?,?,?,?,?)",undef, $paramId,$edition,$centre,4, $discipline,0);
      $dbh->do("insert into grib values (?,?,?,?,?,?)",undef, $paramId,$edition,$centre,8, $pcategory,0);
      $dbh->do("insert into grib values (?,?,?,?,?,?)",undef, $paramId,$edition,$centre,5, $pnumber,0);
      $dbh->do("insert into grib values (?,?,?,?,?,?)",undef, $paramId,$edition,$centre,6, $type1,0)        if ($type1 ne "");
      $dbh->do("insert into grib values (?,?,?,?,?,?)",undef, $paramId,$edition,$centre,13,$type2,0)        if ($type2 ne "");
      $dbh->do("insert into grib values (?,?,?,?,?,?)",undef, $paramId,$edition,$centre,9, $scaledValue1,0) if ($scaledValue1 ne "");
      $dbh->do("insert into grib values (?,?,?,?,?,?)",undef, $paramId,$edition,$centre,7, $scaleFactor1,0) if ($scaleFactor1 ne "");
      $dbh->do("insert into grib values (?,?,?,?,?,?)",undef, $paramId,$edition,$centre,14,$scaledValue2,0) if ($scaledValue2 ne "");
      $dbh->do("insert into grib values (?,?,?,?,?,?)",undef, $paramId,$edition,$centre,15,$scaleFactor2,0) if ($scaleFactor2 ne "");
      $dbh->do("insert into grib values (?,?,?,?,?,?)",undef, $paramId,$edition,$centre,11,$stat,0)         if ($stat ne "");
      $dbh->do("insert into grib values (?,?,?,?,?,?)",undef, $paramId,$edition,$centre,53,$is_chem,0)      if ($is_chem ne "");
      $dbh->do("insert into grib values (?,?,?,?,?,?)",undef, $paramId,$edition,$centre,54,$is_aero,0)      if ($is_aero ne "");
      #$dbh->do("insert into grib values (?,?,?,?,?,?)",undef, $paramId,$edition,$centre,yy,xx,0) if (xx ne "");

      # format is only GRIB2
      $dbh->do("insert into param_format(param_id,grib1,grib2) values (?,?,?)",undef,$paramId,0,1);
    }
} # for each input line

if ($WRITE_TO_FILES) {
    print "Wrote output files: $PARAMID_FILENAME $SHORTNAME_FILENAME $NAME_FILENAME $UNITS_FILENAME $CFVARNAME_FILENAME\n";
    close(OUT_PARAMID)   or die "$PARAMID_FILENAME: $!";
    close(OUT_SHORTNAME) or die "$SHORTNAME_FILENAME: $!";
    close(OUT_NAME)      or die "$NAME_FILENAME: $!";
    close(OUT_UNITS)     or die "$UNITS_FILENAME: $!";
    close(OUT_CFVARNAME) or die "$CFVARNAME_FILENAME: $!";
}

# -------------------------------------------------------------------
sub get_db_units_code {
    my $u = shift;
    return 1  if ($u eq 'm**2 s**-1');
    return 2  if ($u eq 'K');
    return 3  if ($u eq '(0 - 1)');
    return 4  if ($u eq 'm');
    return 5  if ($u eq 'm s**-1');
    return 6  if ($u eq 'J m**-2');
    return 7  if ($u eq '~');
    return 8  if ($u eq 's**-1');
    return 9  if ($u eq 'kg m**-3');
    return 10 if ($u eq 'm**3 m**-3');
    return 12 if ($u eq 's');
    return 14 if ($u eq 'N m**-2 s');
    return 15 if ($u eq 'm**2 s**-2');
    return 16 if ($u eq 'Pa');
    return 17 if ($u eq 'J kg**-1');
    return 18 if ($u eq 'K m**2 kg**-1 s**-1');
    return 19 if ($u eq 'm**2 m**-2');
    return 20 if ($u eq 's m**-1');
    return 21 if ($u eq 'kg kg**-1');
    return 22 if ($u eq 'kg m**-2');
    return 23 if ($u eq 'dimensionless');
    return 26 if ($u eq 'Pa s**-1');
    return 27 if ($u eq 'm of water equivalent');
    return 28 if ($u eq 'gpm');
    return 29 if ($u eq '%');
    return 33 if ($u eq 'kg m**-2 s**-1');

    return 179 if ($u eq 'W');
    return 172 if ($u eq 'W m**-2');
    return 173 if ($u eq 'Index');
    return 174 if ($u eq 'W m**-2');
    return 175 if ($u eq 'kg m**-3');
    return 182 if ($u eq 'Degree N');

    die "Unrecognized units $u\n";
}

sub write_out_file {
    my $outfile = $_[0];
    my $name    = $_[1];
    my $key     = $_[2];

    # Assuming every parameter definition has at least discipline, category and number
    print $outfile "#$name\n";
    print $outfile "'$key' = {\n";
    print $outfile "  discipline = $discipline ;\n";
    print $outfile "  parameterCategory = $pcategory ;\n";
    print $outfile "  parameterNumber = $pnumber ;\n";

    # Optional keys
    print $outfile "  typeOfFirstFixedSurface = $type1 ;\n"                if ($type1 ne "");
    print $outfile "  typeOfSecondFixedSurface = $type2 ;\n"               if ($type2 ne "");
    print $outfile "  scaledValueOfFirstFixedSurface = $scaledValue1 ;\n"  if ($scaledValue1 ne "");
    print $outfile "  scaleFactorOfFirstFixedSurface = $scaleFactor1 ;\n"  if ($scaleFactor1 ne "");
    print $outfile "  scaledValueOfSecondFixedSurface = $scaledValue2 ;\n" if ($scaledValue2 ne "");
    print $outfile "  scaleFactorOfSecondFixedSurface = $scaleFactor2 ;\n" if ($scaleFactor2 ne "");
    print $outfile "  typeOfStatisticalProcessing = $stat ;\n"             if ($stat ne "");
    print $outfile "}\n";
}

sub check_first_row_column_names {
    my $line = shift; # This is the first row
    my @keys = split(/\t/, $line);
    die "Error: 1st row column titles wrong: Column 1 should be 'paramId'\n"   if ($keys[0] ne "paramId");
    die "Error: 1st row column titles wrong: Column 2 should be 'shortName'\n" if ($keys[1] ne "shortName");
    die "Error: 1st row column titles wrong: Column 3 should be 'name'\n"      if ($keys[2] ne "name");
    die "Error: 1st row column titles wrong: Column 4 should be 'units'\n"     if ($keys[3] ne "units");

    die "Error: 1st row column titles wrong: Column 5 should be 'discipline'\n"        if ($keys[4] ne "discipline");
    die "Error: 1st row column titles wrong: Column 6 should be 'parameterCategory'\n" if ($keys[5] ne "parameterCategory");
    die "Error: 1st row column titles wrong: Column 7 should be 'parameterNumber'\n"   if ($keys[6] ne "parameterNumber");

    die "Error: 1st row column titles wrong: Column 8 should be 'typeOfFirstFixedSurface'\n" if ($keys[7] ne "typeOfFirstFixedSurface");
    die "Error: 1st row column titles wrong: Column 9 should be 'scaleFactorOfFirstFixedSurface'\n" if ($keys[8] ne "scaleFactorOfFirstFixedSurface");
    die "Error: 1st row column titles wrong: Column 10 should be 'scaledValueOfFirstFixedSurface'\n" if ($keys[9] ne "scaledValueOfFirstFixedSurface");
    
    die "Error: 1st row column titles wrong: Column 11 should be 'typeOfSecondFixedSurface'\n" if ($keys[10] ne "typeOfSecondFixedSurface");
    die "Error: 1st row column titles wrong: Column 12 should be 'scaleFactorOfSecondFixedSurface'\n" if ($keys[11] ne "scaleFactorOfSecondFixedSurface");
    die "Error: 1st row column titles wrong: Column 13 should be 'scaledValueOfSecondFixedSurface'\n" if ($keys[12] ne "scaledValueOfSecondFixedSurface");
    die "Error: 1st row column titles wrong: Column 14 should be 'typeOfStatisticalProcessing'\n" if ($keys[13] ne "typeOfStatisticalProcessing");
}

sub create_or_append {
    my $outfile = $_[0];
    my $fname   = $_[1];

    if (-f "$fname") {
        open($outfile,  ">>$fname") or die "$fname: $!";
    } else {
        open($outfile,  ">$fname")  or die "$fname: $!";
    }
}

sub is_integer {
    my $val = shift;
    return ($val =~ /^\d+$/);
}
