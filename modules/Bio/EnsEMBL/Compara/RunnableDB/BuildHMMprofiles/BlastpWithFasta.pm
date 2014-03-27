=head1 LICENSE

Copyright [1999-2014] Wellcome Trust Sanger Institute and the EMBL-European Bioinformatics Institute

Licensed under the Apache License, Version 2.0 (the "License");
you may not use this file except in compliance with the License.
You may obtain a copy of the License at

     http://www.apache.org/licenses/LICENSE-2.0

Unless required by applicable law or agreed to in writing, software
distributed under the License is distributed on an "AS IS" BASIS,
WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
See the License for the specific language governing permissions and
limitations under the License.

=cut

=head1 NAME

Bio::EnsEMBL::Compara::RunnableDB::BuildHMMprofiles::BlastpWithFasta

=head1 DESCRIPTION

This module takes in a sequence and perform blastp


=cut
package Bio::EnsEMBL::Compara::RunnableDB::BuildHMMprofiles::BlastpWithFasta;

use strict;
use warnings;
use Bio::EnsEMBL::Utils::Exception qw(throw warning);
use Bio::EnsEMBL::Analysis;
use Bio::EnsEMBL::Analysis::Runnable::Blast;
use Bio::EnsEMBL::Analysis::Runnable::BlastPep;
use Bio::EnsEMBL::Analysis::Tools::BPliteWrapper;
use Bio::EnsEMBL::Analysis::Tools::FilterBPlite;
use Bio::EnsEMBL::Compara::PeptideAlignFeature;   # Blast_reuse
use Bio::Perl;
use Bio::Seq; 
use Bio::SeqIO;
use base ('Bio::EnsEMBL::Compara::RunnableDB::BaseRunnable');

=head2 fetch_input

    Title   :   fetch_input
    Usage   :   $self->fetch_input
    Function:   Retrieving required parameters
    Returns :   none
    Args    :   none

=cut
my $seq; 
my $buildprofiles_dir;
my $wublastp_exe; 
my $blast_options;
my $blast_tmp_dir; 
my $blastDB;

my $regex; 
my $thr_type;
my $thr;
my @cross_pafs;

sub fetch_input {
    my $self = shift @_;
   
    $seq               = $self->param('seq'); 
    $buildprofiles_dir = $self->param('buildprofiles_dir');
    $wublastp_exe      = $self->param('wublastp_exe');
    die "Cannot execute '$wublastp_exe'" unless(-x $wublastp_exe);
    $blast_options     = $self->param('blast_options');        
    $blast_tmp_dir     = $self->param('blast_tmp_dir');
    $blastDB           = $buildprofiles_dir."/BLASTDB";

    $self->throw('seq is an obligatory parameter') unless (defined $self->param('seq'));
    $self->throw('wublastp_exe is an obligatory parameter') unless (defined $self->param('wublastp_exe'));
    $self->throw('buildprofiles_dir is an obligatory parameter') unless (defined $self->param('buildprofiles_dir'));
    $self->throw('blast_options is an obligatory parameter') unless (defined $self->param('blast_options'));
    $self->throw('blast_tmp_dir is an obligatory parameter') unless (defined $self->param('blast_tmp_dir'));

    $self->check_directory($blast_tmp_dir);
    # Define BLAST Parser Filter Object parameters
    # From Bio/EnsEMBL/Analysis/Config/Blast.pm
    $regex         = $self->param('regex') || '^(\S+)\s*';
    $thr_type      = $self->param('-threshold_type');
    $thr           = $self->param('-threshold');
        
    unless($thr_type and $thr) {
      ($thr_type, $thr) = ('PVALUE', 1e-10);
    }	
return;
}

=head2 run

  Arg[1]     : -none-
  Example    : $self->run;
  Function   : Create and run the Blast runnable
  Returns    : 1 on successful completion
  Exceptions : dies if runnable throws an unexpected error

=cut
sub run {
    my $self = shift @_;

    my $id              = $seq->id;	
    my $fake_analysis	= Bio::EnsEMBL::Analysis->new;
    ## Create a parser object. This Bio::EnsEMBL::Analysis::Tools::FilterBPlite
    ## object wraps the Bio::EnsEMBL::Analysis::Tools::BPliteWrapper which in
    ## turn wraps the Bio::EnsEMBL::Analysis::Tools::BPlite (a port of Ian
    ## Korf's BPlite from bioperl 0.7 into ensembl). This parser also filter
    ## the results according to threshold_type and threshold.
    my $parser = Bio::EnsEMBL::Analysis::Tools::FilterBPlite->new(
        	-regex          => $regex,
	 	-query_type     => 'pep',
        	-database_type  => 'pep',
		-input_type     => 'pep',
        	-threshold_type => $thr_type,
        	-threshold      => $thr,
      		);
    ## Create the runnable with the previous parser. The filter is not required:
    my $runnable = Bio::EnsEMBL::Analysis::Runnable::BlastPep->new(
		-query     => $seq,
         	-database  => $blastDB,
         	-program   => $wublastp_exe,
                -analysis  => $fake_analysis,
                -options   => $blast_options,
                -parser    => $parser,
                -filter    => undef,
                 	( $blast_tmp_dir ? (-workdir => $blast_tmp_dir) : () ),				
		);

    $self->compara_dba->dbc->disconnect_when_inactive(1);
    $self->compara_dba->dbc->disconnect_if_idle() if $self->compara_dba->dbc->connected();
    ## call runnable run method in eval block
    eval { $runnable->run($blast_tmp_dir); };

    ## Catch errors if any
    if ($@) {
             print STDERR ref($runnable)." threw exception:\n$@$_";
             if($@ =~ /"VOID"/) {
               	print STDERR "this is OK: UniPARC_id='$id' doesn't have sufficient structure for a search\n";
             } else {
                die("$@$_");
             }
    }
    #since the Blast runnable takes in analysis parameters rather than an
    #analysis object, it creates new Analysis objects internally
    #(a new one for EACH FeaturePair generated)
    #which are a shadow of the real analysis object ($self->analysis)
    #The returned FeaturePair objects thus need to be reset to the real analysis object
    my %cross_pafs = ();# for storing blast output

    foreach my $feature (@{$runnable->output}) {
	if($feature->isa('Bio::EnsEMBL::FeaturePair')) {
 		$feature->{null_cigar} = 1 if ($self->param('null_cigar'));
        }
	push @{$cross_pafs{'1'}}, $feature; # using 1 as genome_db ID for all sequences
     }
     $self->param('cross_pafs',\%cross_pafs);
     undef $seq;

return;	
}

sub write_output {
    my $self = shift @_;

    print STDERR "Inserting blast output into peptide_align_feature tables...\n" if ($self->debug);
    my $cross_pafs = $self->param('cross_pafs');
    $self->compara_dba->get_PeptideAlignFeatureAdaptor->store(@{$cross_pafs->{'1'}});

return;
}

=head2 check_directory

  Arg[1]     : -none-
  Example    : $self->check_directory;
  Function   : Check if the directory exists, if not create it
  Returns    : None
  Exceptions : dies if fail when creating directory 

=cut
sub check_directory {
    my ($self,$dir) = @_;

    unless (-e $dir) {
        print STDERR "$dir doesn't exists. I will try to create it\n" if ($self->debug());
        print STDERR "mkdir $dir (0755)\n" if ($self->debug());
        die "Impossible create directory $dir\n" unless (mkdir $dir, 0755 );
    }

return;
}

1;