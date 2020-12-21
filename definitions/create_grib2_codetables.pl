use strict;

# ------------------------------------------------------------------------
# Get the CodeFlag.txt file from WMO
# Convert it to TSV (tab-separated-values format):
#  perl csv_2_tsv.pl CodeFlag.txt
# This will create the file CodeFlag.txt.tsv
# Create the directory corresponding to the new GRIB2 version:
#  mkdir -p definitions/grib2/tables/xx
# cd to that directory:
#  cd definitions/grib2/tables/xx
# Run this script on that TSV file:
#  perl create_codetables.pl < /path/to/CodeFlag.txt.tsv
# This should create all the *.table files
# ------------------------------------------------------------------------

# Types of title_en
# Code table 0.0 - Discipline of processed data in the GRIB message, number of GRIB Master table
# Code table 4.1 - Parameter category by product discipline  --> "Product discipline 0 - XXX"
# Code table 4.2 - Parameter number by product discipline and parameter category  --> "Product discipline 0 - YY, parameter category 0: XX"
# Flag table 3.9 - Numbering order of diamonds as seen from the corresponding pole

#Product Discipline 0 - Meteorological products, parameter category 16: forecast radar imagery

my $recnum = 0;
my $codetable; my $discipline; my $category; my $filename;
while (<>) {
    ++$recnum;
    next if ($recnum==1);

    # OLD FORMAT had initial "No" column
    #No Title_en    SubTitle_en    CodeFlag    Value    MeaningParameterDescription_en  Note_en UnitComments_en  Status
    #my ($rowid, $title, $subtitle, $codeFlag, $value, $meaning, $note, $unit, $status) = split(/\t/);
    
    my ($title, $subtitle, $codeFlag, $value, $meaning, $note, $unit, $status) = split(/\t/);
    
    if ($title =~ /Code table ([0-9.]+)/) {
        $codetable = $1;
        if ($subtitle =~ /Product [Dd]iscipline (\d+).*parameter category (\d+)/) {
            $discipline = $1;
            $category = $2;
            $filename = "$codetable.$discipline.$category.table";
            WriteFile($filename, $title, $codeFlag, $meaning, $unit);
        }
        elsif ($subtitle =~ /Product discipline (\d+)/) {
            $discipline = $1;
            $filename = "$codetable.$discipline.table";
            WriteFile($filename, $title, $codeFlag, $meaning, $unit);
        }
        elsif ($subtitle eq "") {
            $filename = "$codetable.table";
            WriteFile($filename, $title, $codeFlag, $meaning, $unit);
        }
    } elsif ($title =~ /Flag table ([0-9.]+)/) {
        $codetable = $1;
        $filename = "$codetable.table";
        WriteFlagTable($filename, $title, $codeFlag, $value, $meaning, $unit);
    }

    #exit if ($recnum >800);
}
###################################################################################################
sub WriteFile {
    my($filename, $title, $codeFlag, $meaning, $unit) = @_;
    if (!-e $filename) {
        print "Creating $filename\n";
        open (MYFILE, ">>$filename");
        #print MYFILE "# Automatically generated by ./create_tables.pl from database fm92_grib2\@wrep-db-misc-prod, do not edit\n";
        print MYFILE "# $title\n";
    }
    my $unit_text = ($unit eq "" ? "" : "($unit)");
    if ($codeFlag =~ /\-/) {
        print MYFILE "# $codeFlag $meaning $unit_text\n";
    } else {
        my $codeFlag1 = $codeFlag;
        my $codeFlag2 = $codeFlag;
        if ($filename eq "1.4.table") {
            # Special case. Do not just put 2nd code, translate it to shortName for 'mars type'
            $codeFlag2 = TranslateCodes_Table_1_4($codeFlag);
        }
        elsif ($filename eq "4.4.table") {
            $codeFlag2 = TranslateCodes_Table_4_4($codeFlag);
        }
        elsif ($filename eq "4.5.table") {
            $codeFlag2 = TranslateCodes_Table_4_5($codeFlag);
        }
        elsif ($filename eq "3.15.table") {
            $codeFlag2 = TranslateCodes_Table_3_15($codeFlag);
        }
        elsif ($filename eq "4.10.table") {
            $codeFlag2 = TranslateCodes_Table_4_10($codeFlag);
        }
        print MYFILE "$codeFlag1 $codeFlag2 $meaning $unit_text\n";
    }
}

###################################################################################################
sub WriteFlagTable{
    my($filename, $title, $codeFlag, $value, $meaning, $unit) = @_;
    if (!-e $filename) {
        print "Creating $filename\n";
        open (MYFILE, ">>$filename");
        #print MYFILE "# Automatically generated by ./create_tables.pl from database fm92_grib2\@wrep-db-misc-prod, do not edit\n";
        print MYFILE "# $title\n";
    }
    my $unit_text = ($unit eq "" ? "" : "($unit)");
    if ($codeFlag =~ /\-/) {
        print MYFILE "# $codeFlag $meaning $unit_text\n";
    } else {
        print MYFILE "$codeFlag $value $meaning $unit_text\n";
    }
}

###################################################################################################
sub TranslateCodes_Table_4_10 {
    my ($code) = @_;
    return "avg"   if ($code == 0);
    return "accum" if ($code == 1);
    return "max"   if ($code == 2);
    return "min"   if ($code == 3);
    return "diff"  if ($code == 4);
    return "rms"   if ($code == 5);
    return "sd"    if ($code == 6);
    return "cov"   if ($code == 7);
    return "ratio" if ($code == 9);
    return "missing" if ($code == 255);
    return $code;
}
sub TranslateCodes_Table_3_15 {
    my ($code) = @_;
    return "pt" if ($code == 107);
    return "pv" if ($code == 109);
    return $code;
}

###################################################################################################
# This is for Code Table 1.4
sub TranslateCodes_Table_1_4 {
    my ($code) = @_;
    return "an" if ($code eq "0");
    return "fc" if ($code eq "1");
    return "af" if ($code eq "2");
    return "cf" if ($code eq "3");
    return "pf" if ($code eq "4");
    return "cp" if ($code eq "5");
    return "sa" if ($code eq "6");
    return "ra" if ($code eq "7");
    return "ep" if ($code eq "8");
    return "missing" if ($code eq "255");
    return $code;
}

###################################################################################################
sub TranslateCodes_Table_4_4 {
    my ($code) = @_;
    return "m"    if ($code eq "0");
    return "h"    if ($code eq "1");
    return "D"    if ($code eq "2");
    return "M"    if ($code eq "3");
    return "Y"    if ($code eq "4");
    return "10Y"  if ($code eq "5");
    return "30Y"  if ($code eq "6");
    return "C"    if ($code eq "7");
    return "3h"   if ($code eq "10");
    return "6h"   if ($code eq "11");
    return "12h"  if ($code eq "12");
    return "s"    if ($code eq "13");
    return $code;
}

###################################################################################################
sub TranslateCodes_Table_4_5 {
    my ($code) = @_;
    return "sfc"  if ($code eq "1" || $code eq "8" || $code eq "17" || $code eq "18" ||
            $code eq "101" || $code eq "103" || $code eq "106" || $code eq "177");
    return "pl"   if ($code eq "100");
    return "ml"   if ($code eq "105");
    return "pt"   if ($code eq "107");
    return "pv"   if ($code eq "109");
    return "hhl"  if ($code eq "118");
    return "hpl"  if ($code eq "119");
    return "sol"  if ($code eq "151");
    return "sol"  if ($code eq "114");
    return "sol"  if ($code eq "152");
    return $code;
}
