use ExtUtils::MakeMaker;
# See lib/ExtUtils/MakeMaker.pm for details of how to influence
# the contents of the Makefile that is written.
WriteMakefile(
	'NAME'		=>	'POE::Component::Server::SimpleHTTP',
	'VERSION_FROM'	=>	'lib/POE/Component/Server/SimpleHTTP.pm', # finds $VERSION
	'PREREQ_PM'	=> {
		'HTTP::Date'			=>	0,
		'Carp'				=>	0,
		'Sys::Hostname'			=>	0,
		'POE'				=>	'0.27',
		'POE::Wheel::ReadWrite'		=>	0,
		'POE::Driver::SysRW'		=>	0,
		'POE::Filter::HTTPD'		=>	0,
		'POE::Wheel::SocketFactory'	=>	0,
		'Storable'			=>	0,
		'Socket'			=>	0,
		'HTTP::Request'			=>	0,
		'HTTP::Response'		=>	0,
	},
	'ABSTRACT_FROM'	=> 'lib/POE/Component/Server/SimpleHTTP.pm', # retrieve abstract from module
	'AUTHOR'	=> 'Apocalypse <APOCAL@cpan.org>',
);