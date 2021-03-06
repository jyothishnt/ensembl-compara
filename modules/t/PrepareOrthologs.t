#!/usr/bin/env perl
use strict;
use warnings;

use Data::Dumper;
use Bio::EnsEMBL::Hive::Utils::Test qw(standaloneJob);
use Bio::EnsEMBL::Hive::DBSQL::DBConnection;
use Bio::EnsEMBL::Test::MultiTestDB;

BEGIN {
    use Test::Most;
}

# check module can be seen and compiled
use_ok('Bio::EnsEMBL::Compara::RunnableDB::OrthologQM::PrepareOrthologs'); 

my $exp_dataflow;

# Load test DB #
my $multi_db = Bio::EnsEMBL::Test::MultiTestDB->new('orth_qm_wga');
my $dba = $multi_db->get_DBAdaptor('cc21_prepare_orth');
my $dbc = Bio::EnsEMBL::Hive::DBSQL::DBConnection->new(-dbconn => $dba->dbc);
my $compara_db = $dbc->url;

# Test on pair of species without reuse #
$exp_dataflow = [
	{ orth_batch => [
		{   id => 101, 
			orth_ranges => { 134 => [41216073, 41216526], 150 => [33638035, 33638494]}, 
			orth_dnafrags => [ 
				{ id => 13705550, start => 41216073, end => 41216526 },
				{ id => 13955529, start => 33638035, end => 33638494 },
			],
			exons => { 134 => [[1,1000]], 150 => [[1,1000]] },
		}
	]},
	{ orth_batch => [
		{   id => 102, 
			orth_ranges => { 134 => [41227505, 41227993], 150 => [33638035, 33638494]}, 
			orth_dnafrags => [
				{ id => 13705550, start => 41227505, end => 41227993 },
				{ id => 13955529, start => 33638035, end => 33638494 }
			],
			exons => { 134 => [[1,1000]], 150 => [[1,1000]] },
		}
	]},
	{ orth_batch => [
		{   id => 103, 
			orth_ranges => { 134 => [41216073, 41216526], 150 => [142645961, 142646467]}, 
			orth_dnafrags => [
				{ id => 13705550, start => 41216073,  end => 41216526  },
				{ id => 13955533, start => 142645961, end => 142646467 },
			],
			exons => { 134 => [[1,1000]], 150 => [[1,1000]] },
		}
	]},
];

standaloneJob(
	'Bio::EnsEMBL::Compara::RunnableDB::OrthologQM::PrepareOrthologs', # module
	{ # input param hash
		'species1_id'     => '150',
		'species2_id'     => '134',
		'compara_db'      => $compara_db,
		'orth_batch_size' => 1,
	},
	[ # list of events to test for (just 1 event in this case)
		[ # start event
			'DATAFLOW', # event to test for (could be WARNING)
			$exp_dataflow, # expected data flowed out
			2 # dataflow branch
		], # end event
	]
);

# Test on pair of species with reuse #
my $dba_prev = $multi_db->get_DBAdaptor('cc21_prev_orth_test');
my $dbc_prev = Bio::EnsEMBL::Hive::DBSQL::DBConnection->new(-dbconn => $dba_prev->dbc);
my $prev_compara_db = $dbc_prev->url;

my $exp_dataflow_1 = { # expecting the reusable homology ids
	previous_rel_db  => $prev_compara_db, #url
	current_db       => $compara_db,
	homology_ids     => [[102, 2], [103, 3]],
};

my $exp_dataflow_2 = [  { orth_batch => 
	[ 
		{   id => 101, 
			orth_ranges => { 134 => [41216073, 41216526], 150 => [33638035, 33638494]}, 
			orth_dnafrags => [ 
				{ id => 13705550, start => 41216073, end => 41216526 },
				{ id => 13955529, start => 33638035, end => 33638494 },
			],
			exons => { 134 => [[1,1000]], 150 => [[1,1000]] }, 
		}
	]
}];

standaloneJob(
	'Bio::EnsEMBL::Compara::RunnableDB::OrthologQM::PrepareOrthologs', # module
	{ # input param hash
		'species1_id'     => '150',
		'species2_id'     => '134',
		'compara_db'      => $compara_db,
		'previous_rel_db' => $prev_compara_db,
		'orth_batch_size' => 1

	},
	[ # list of events to test for (just 1 event in this case)
		[ # start event
			'DATAFLOW', # event to test for (could be WARNING)
			$exp_dataflow_2, # expected data flowed out
			2 # dataflow branch
		], # end event
		[
			'DATAFLOW',
			$exp_dataflow_1,
			1
		],
	]
);

done_testing();