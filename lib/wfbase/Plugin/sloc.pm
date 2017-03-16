package wfbase::Plugin::sloc;

my $strings;
my $index;

sub setup
{
	use Config::Any;
	my $app=shift;
	my $conf=eval "${app}->config";
	my @locales=($conf->{locale},@{$conf->{locales}});

	$strings={
		%{(values %{Config::Any->load_files({files=>["$wfbase::base/strings.yaml"],use_ext=>1})->[0]})[0]},
		%{(values %{Config::Any->load_files({files=>["$wfbase::home/strings.yaml"],use_ext=>1})->[0]})[0]},
	};

	
	foreach my $co (keys %$strings)
	{
		print "co $co\n";
		foreach my $te (@{$strings->{$co}})
		{
			my @p=map {ref $_ eq 'HASH'?(%$_):$_} @$te;
			for (my $i=0;$i<@p; $i+=2)
			{
				for (my $j=1;$j<@p;$j+=2)
				{
					my ($a,$b)=($p[$i],$p[$j]);
					next if $a eq $p[$j-1] or $b eq $p[$j+1];
					$index->{$co}{$a}{$b}=$p[$j-1] if !@locales or grep {$b eq $_} @locales;
					$index->{$co}{$b}{$a}=$p[$i+1] if !@locales or grep {$a eq $_} @locales;;
				};
			};
		};
	};
	
}
sub loc
{
	my ($c,$s,$co)=@_;
	return $index->{$co}{$s}{$c->config->{locale}} || $s if $co;
	return $_->{$s}{$c->config->{locale}} foreach grep {$_->{$s}{$c->config->{locale}}} values %$index;
	return $s;

}
1;
