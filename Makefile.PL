use 5.008;
use ExtUtils::MakeMaker;
# See lib/ExtUtils/MakeMaker.pm for details of how to influence
# the contents of the Makefile that is written.
WriteMakefile(
	'NAME'		=>	'POE::Component::Server::SimpleHTTP',
	'VERSION_FROM'	=>	'lib/POE/Component/Server/SimpleHTTP.pm', # finds $VERSION
	'PREREQ_PM'	=> {
		'HTTP::Status'			=>	0,
		'HTTP::Date'			=>	0,
		'Socket'			=>	0,
		'Carp'				=>	0,
		'Sys::Hostname'			=>	0,
		'POE'				=>	'0.27',
		'POE::Session'			=>	0,
		'POE::Wheel::ReadWrite'		=>	0,
		'POE::Driver::SysRW'		=>	0,
		'POE::Filter::Stream'		=>	0,
		'POE::Filter::HTTPD'		=>	0,
		'POE::Component::Server::TCP'	=>	0,
		'Storable'			=>	0,
	},
	'ABSTRACT_FROM'	=> 'lib/POE/Component/Server/SimpleHTTP.pm', # retrieve abstract from module
	'AUTHOR'	=> 'Apocalypse <APOCAL@cpan.org>',
);