#!perl
use NAP::policy 'test','tt';
use NAP::Messaging::Validator;

my $v = NAP::Messaging::Validator->build_validator({ type => '/nap/datetime' });

sub ok_datetime {
    my ($dt) = @_;
    cmp_deeply([NAP::Messaging::Validator->validate($v,$dt)],
               [1],
               "<$dt> is valid");
}
sub nok_datetime {
    my ($dt) = @_;
    cmp_deeply([NAP::Messaging::Validator->validate($v,$dt)],
               [0,ignore()],
               "<$dt> is not valid");
}

ok_datetime('1970-01-01');
ok_datetime('1970-01-01T00:00:00');
ok_datetime('1970-01-01T00:00:00.000');
ok_datetime('1970-01-01T00:00:00.000+0000');
ok_datetime('2014-01-15T10:55:26.000+0000');
ok_datetime('1970-01-01T00:00:00.000+00:00');
nok_datetime('1970-02-30T00:00:00.000+00:00');
ok_datetime('1970-01-01T00:00:00.000-0000');
ok_datetime('2014-01-15T10:55:26.000-0000');
ok_datetime('1970-01-01T00:00:00.000-00:00');
nok_datetime('1970-02-30T00:00:00.000-00:00');
nok_datetime('not a date');
nok_datetime('today');

done_testing;
