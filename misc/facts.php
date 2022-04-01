<?php

## Ansible Fact Wrapper with Caching

#  This was no suppose to be a benchmarking script, just a small 
#  dynmatic config helper, to pick the order of ciphers of ssh 
#  to best leverage AES-NI on Intel CPUs, and if the VM would be 
#  restarted on a different generator of CPU, readjust to a more
#  optimal cipher order.

# to be run as root.


function parseArgs() {
	$longopts  = array(
		"str:",
	);

	$options = getopt("", $longopts);
	return $options;
}



function dmi($fields = array('system-uuid', 'baseboard-serial-number', 'chassis-serial-number', 'system-serial-number', 'bios-vendor', 'bios-version', 'system-manufacturer', 'system-product-name', 'system-version')) 
{

	$retval = array();

	foreach ($fields as $f) {
		$x = `dmidecode -s $f`;
		$x = rtrim($x);
		echo "==> $f : $x\n";
		$retval[$f] = $x;
	}

	return $retval;
}


function ssh_aesni() 
{

	$str = `cpuid`;
	$aesni = false;
	foreach ( preg_split ("/\n/", $str )  as $line ) {
		if ( preg_match ("/(AESNI|AES instruction)/i", $line ) ) 
		{
			$aesni = true;
			break;
		}
	}
	if ( $aesni ) {	
		$c =`ssh -Q cipher`;
		if ( !is_dir ("/aesni-speedtest") ) 
		{
			mkdir("/aesni-speedtest");
		}

		$mount_type = `df /aesni-speedtest`;
		if ( !preg_match("/tmpfs/", $mount_type) ) 
		{
			`mount -t tmpfs tmpfs /aesni-speedtest`;
			$mount_type = `df /aesni-speedtest`;
			if ( !preg_match("/tmpfs/", $mount_type) ) 
			{
				die("couldn't mount tmpfs");
			}
		}
		$tmpfname = tempnam("/aesni-speedtest", "ssh-aesni-testing.bin");
		echo "Filename : $tmpfname \n";
		system("dd if=/dev/urandom bs=4096 count=16384 of=$tmpfname");
		system("ls -l $tmpfname");
		$HOME = getenv('HOME');
		@unlink("$HOME/.ssh/aesni-speedtest.pub");
		@unlink("$HOME/.ssh/aesni-speedtest");		
		`ssh-keygen -C "aesni-speedtest" -f $HOME/.ssh/aesni-speedtest -N ""`;
		$SSHD = "/usr/sbin/sshd";
		if ( !is_executable($SSHD) )
		{ 
			if ( is_executable("/sbin/sshd") ) {
				$SSHD = "/sbin/sshd";
			} else {
				die ("can't find the sshd binary.");
			}
		}		
		`$SSHD -p 2222 -o ListenAddress=127.0.0.1:2222 -o AuthorizedKeysFile=.ssh/aesni-speedtest.pub -o PidFile=/run/sshd-2222.pid`;

		$timedChipers = array();		
		foreach ( preg_split ("/\n/", $c) as $chiper ) {
			if ( !preg_match("/aes/", $chiper) ) { continue; }
			if ( preg_match("/cbc/", $chiper) ) { continue; }
			$cmd="cat $tmpfname | ssh -i $HOME/.ssh/aesni-speedtest -m umac-64-etm@openssh.com -c $chiper -o UpdateHostKeys=yes -o Compression=no -o StrictHostKeyChecking=no -p 2222 127.0.0.1 \"cat > /dev/null\"";
			# echo "CMD: $cmd \n";
			$total=0;
			for ($i=0; $i<5; $i++) {
				$eta=0;
				$eta=-hrtime(true);
				system($cmd);
				$eta+=hrtime(true);
				printf ( " %4.02f $chiper\n", $eta );
				$total+=$eta;
			}
			$timedChipers[$chiper] = $total/$i/1e+6; //nanoseconds to milliseconds
			printf ( " %.02f avg $chiper\n", $timedChipers[$chiper] );
		}
		
		asort ( $timedChipers, SORT_NUMERIC);
		system ("kill `cat /run/sshd-2222.pid`");
		unlink($tmpfname);
		unlink("$HOME/.ssh/aesni-speedtest.pub");
		unlink("$HOME/.ssh/aesni-speedtest");
		system("umount /aesni-speedtest");
		
		print_r ( $timedChipers );
		
		
	}

}


$opt = parseArgs();
#print_r ( $opt );

$x = dmi();

print_r ( $x );

#echo json_encode ($x);
ssh_aesni();

?>
