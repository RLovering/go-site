#!/usr/bin/perl -w
use strict;
use JSON;
    
# This replaces filter-gaf.pl

my $json = new JSON;
my $datasets;
my $dsname;
my $err_fh;
my $report_fh;
my $noiea_file;

while (scalar(@ARGV) && $ARGV[0] =~ m@^\-@) {
    my $opt = shift @ARGV;
    if ($opt eq '-m' || $opt eq '--meta') {
        my $mf = shift @ARGV;
        open(F, $mf) || die $mf;
        my $blob = join("",<F>);
        $datasets = $json->decode( $blob );
        close(F);
    }
    elsif ($opt eq '-p' || $opt eq '--project') {
        $dsname = shift @ARGV;
    }
    elsif ($opt eq '-e' || $opt eq '--err') {
        my $errfile = shift @ARGV;
        open $err_fh, '>', $errfile or die "Cannot open $errfile";
    }
    elsif ($opt eq '-r' || $opt eq '--report') {
        my $repfile = shift @ARGV;
        open $report_fh, '>', $repfile or die "Cannot open $repfile";
    }
    elsif ($opt eq '--noiea-file') {
        $noiea_file = shift @ARGV;
    }
    else {
        die $opt;
    }
}

if (!$err_fh) {
    $err_fh = *stderr;
}

my @all_taxa = ();
foreach (@$datasets) {
    push(@all_taxa, @{$_->{taxa} || []});
}
my %all_taxa_map = map { ($_=>1) } @all_taxa;

my @matches = grep { $_->{dataset} eq $dsname } @$datasets;
my $ds;
if (@matches > 0) {
    $ds = shift @matches;
}
else {
    die "No matches for $dsname ";
}

my $is_aggregated = 0;
if ($ds->{aggregates}) {
    $is_aggregated = 1;
}

my %taxcheckmap = ();

foreach my $t (@{$ds->{taxa}}) {
    $taxcheckmap{$t} = 1;
}

my $noiea_fh;
if ($noiea_file) {
    open $noiea_fh, '>', $noiea_file or die "Cannot open $noiea_file";
}


my $n_rows = 0;
my $n_rows_ok = 0;
my $n_rows_err = 0;
my $n_errs = 0;
my $n_filtered = 0;
while(<>) {
    $n_rows++;
    chomp;
    if (m@^\!@) {
        if (m@gaf_version@) {
            warn("Fixing line: $_");
            s@gaf_version@gaf-version@;
        }
        print "$_\n";
        next;
    }
    
    my ($db,
        $db_object_id,
        $db_object_symbol,
        $qualifier,
        $goid,
        $reference,
        $evidence,
        $with,
        $aspect,
        $db_object_name,
        $db_object_synonym,
        $db_object_type,
        $taxon,
        $date,
        $assigned_by,
        $annotation_xp,
        $gene_product_isoform,
        ) = split(/\t/, $_);

    # reset
    my @errors = ();

    $taxon =~ s@taxon@NCBITaxon@;
    if ($is_aggregated) {
        # check if this taxon is covered by another group
        if ($all_taxa_map{$taxon}) {
            $n_filtered++;
            next;
        }
    }
    else {
        if (!$taxcheckmap{$taxon}) {
            push(@errors, 
                 sprintf('INVALID_TAXON: %s for %s; Expected=%s', $taxon, $dsname, join(" OR ", keys %taxcheckmap)));
        }
    }

    my @withs = split(/[\|\,]/, $with);
    my @bad_withs = grep {is_bad_xref($_)} @withs;

    if (@bad_withs) {
        push(@errors, 
             sprintf('BAD_DB: %s', join(", ", @bad_withs)));
    }

    # END OF ERROR CHECKING
    
    if (@errors) {
        report_errors($_, @errors);
        $n_rows_err++;
        $n_errs += scalar(@errors);
        next;
    }

    $_ = join("\t", ($db,
        $db_object_id,
        $db_object_symbol,
        $qualifier,
        $goid,
        $reference,
        $evidence,
        $with,
        $aspect,
        $db_object_name,
        $db_object_synonym,
        $db_object_type,
        $taxon,
        $date,
        $assigned_by,
        $annotation_xp,
        $gene_product_isoform,
              ));

    
    print "$_\n";

    if ($noiea_fh) {
        if ($evidence ne 'IEA') {
            print $noiea_fh "$_\n";
        }
    }
    
    $n_rows_ok++;
}

if (!$report_fh) {
    $report_fh = *stderr;
}
print $report_fh "## Report for: $dsname\n\n";
print $report_fh " * total errors: $n_errs\n";
print $report_fh " * total filtered: $n_filtered\n";
print $report_fh " * total rows: $n_rows\n";
print $report_fh " * total rows OK: $n_rows_ok\n";
print $report_fh " * total rows with errors: $n_rows_err\n";

$err_fh->close() if $err_fh;
$report_fh->close() if $report_fh;
$noiea_fh->close() if $noiea_fh;

exit 0;

sub is_bad_xref {
    if (m@^DB:@) {
        return 1;
    }
    return 0;
}

sub report_errors {
    my ($line, @line_errs) = @_;
    print $err_fh "! BAD: $line\n";
    print $err_fh "! ERR: @line_errs\n\n";
}
