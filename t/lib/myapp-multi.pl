#!perl
use NAP::policy 'tt';
use NAP::Messaging::MultiRunner::Partitioned;
NAP::Messaging::MultiRunner::Partitioned->new('MyApp')->run_multiple;
