#!/usr/bin/perl
#
# This program will allow you to calculate the offset inside the binary for patching purposes
# (c) 2011 Fractal Guru - reverse\@put.as - http://reverse.put.as
#
# Feel free to do whatever you want with this code (keep the credits!) 
#
# * THIS SOFTWARE IS PROVIDED BY THE AUTHOR AND CONTRIBUTORS "AS IS"
# * AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE
# * IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE
# * ARE DISCLAIMED. IN NO EVENT SHALL THE AUTHOR OR CONTRIBUTORS BE
# * LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR
# * CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF
# * SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS
# * INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN
# * CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE)
# * ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE
# * POSSIBILITY OF SUCH DAMAGE.
#
my $VERSION = "1.3";
# change me to 1 to have debug messages
my $debug = 0;

my %table;
my $buffer = "";

my $info = <<INFO;
Mach-o Binary Offset Calculator v$VERSION
....................................
(c) 2011 fG! - http://reverse.put.as - reverse\@put.as

Usage: $0 <file> [offset] [x86/ppc/x64/arm/armv6/armv7]

Where:
<file>   = File to calculate offset from
[offset] = Offset from otx/otool (in hexadecimal format!)
[x84]     = To calculate offset for x86 architecture
[x64]     = To calculate offset for x64 architecture
[ppc]     = To calculate offset for PPC architecture
[arm]     = To calculate offset for ARM_ALL architecture
[armv6]   = To calculate offset for ARM_V6 architecture
[armv7]   = To calculate offset for ARM_V7 architecture

Default mode is interactive

Example for interactive mode:
$0 /bin/ls

Example for x86:
$0 /bin/ls 23f0 x86

Example for PPC:
$0 /bin/ls 16a4 ppc

Example for x64:
$0 /bin/ls 16a4 x64

INFO

my $header = <<HEADER;
Mach-o Binary Offset Calculator v$VERSION
....................................
(c) 2011 fG! - http://reverse.put.as - reverse\@put.as

HEADER

sub help
{
	print $info;
	exit 1;
}

if (!defined($ARGV[0]))
{
	help();
}

my $filetoopen = $ARGV[0];
if (! -e $filetoopen)
{
	print $header;
	print "ERROR: Can't access file $filetoopen !\n";
	exit(1);
}

$mode = 0;
if (defined($ARGV[1]) && defined($ARGV[2]))
{
	$mode = 1;
	$myoffset = hex($ARGV[1]);
	# architecture to calculate offset for
	$target = "x86" if (lc($ARGV[2]) eq "x86");;
	$target = "ppc" if (lc($ARGV[2]) eq "ppc");
	$target = "x64" if (lc($ARGV[2]) eq "x64");
	$target = "arm" if (lc($ARGV[2]) eq "arm");
	$target = "armv6" if (lc($ARGV[2]) eq "armv6");
	$target = "armv7" if (lc($ARGV[2]) eq "armv7");
}

print $header;

# create filehandle
open(FILE,"<$filetoopen");
#struct fat_header @ /usr/include/mach-o/fat.h
#{ 
#    uint32_t magic; 
#    uint32_t nfat_arch; 
#}; 
# Total Size: 8 bytes
sysseek(FILE,0,0);
sysread(FILE, $buffer, 8);
# this is always big-endian
my ($magicheader, $nfat_arch) = unpack("NN", $buffer);
printf("Magic Header: 0x%x\n", $magicheader) if $debug;
# if it's a fat binary we need to find where the i386 binary is
my %baseaddresses;
if ($magicheader == 0xcafebabe)
{
	printf("Found a Mach-O fat binary with %d architectures!\n", $nfat_arch);
	print "Finding available architectures and their base addresses...\n" if $debug;
	#struct fat_arch @ /usr/include/mach-o/fat.h
	#{ 
    #	cpu_type_t cputype; 
    #	cpu_subtype_t cpusubtype; 
    #	uint32_t offset; 
    #	uint32_t size; 
    #	uint32_t align; 
	#}; 
	# Total Size: 20 bytes
	$initialposition = sysseek(FILE, 0, 1);
	# read info from all available binaries inside
	for ($i=0; $i < $nfat_arch; $i++)
	{
		sysread(FILE, $buffer, 20);
		# retrieve the info for a specific architecture
		($fatinfo[$i]->{'cputype'}, $fatinfo[$i]->{'cpusubtype'}, $fatinfo[$i]->{'offset'}, $fatinfo[$i]->{'size'}, $fatinfo[$i]->{'align'}) = unpack("NNNNN", $buffer);
		printf("Found architecture %d\n", $fatinfo[$i]->{'cputype'}) if $debug;
		# and now verify what is the structure
		# machine types defined @ /usr/include/mach/machine.h
		# x86
		if ($fatinfo[$i]->{'cputype'} == 7) { $baseaddresses{'x86'} = $fatinfo[$i]->{'offset'}; }
		# PPC
		elsif ($fatinfo[$i]->{'cputype'} == 18) { $baseaddresses{'ppc'} = $fatinfo[$i]->{'offset'}; }
		# x64
		elsif ($fatinfo[$i]->{'cputype'} == 16777223) { $baseaddresses{'x64'} = $fatinfo[$i]->{'offset'}; }
		# PPC_64
		elsif ($fatinfo[$i]->{'cputype'} == 16777234) { $baseaddresses{'ppc64'} = $fatinfo[$i]->{'offset'}; }
		# ARM_ALL
		elsif ($fatinfo[$i]->{'cputype'} == 12 && $fatinfo[$i]->{'cpusubtype'} == 0x0) { $baseaddresses{'arm'} = $fatinfo[$i]->{'offset'}; }
		# ARM_V6
		elsif ($fatinfo[$i]->{'cputype'} == 12 && $fatinfo[$i]->{'cpusubtype'} == 0x6) { $baseaddresses{'armv6'} = $fatinfo[$i]->{'offset'}; }
		# ARM_V7
		elsif ($fatinfo[$i]->{'cputype'} == 12 && $fatinfo[$i]->{'cpusubtype'} == 0x9) { $baseaddresses{'armv7'} = $fatinfo[$i]->{'offset'}; }
	}
# if it's a i386 only binary then base address is 0
}
# x86 or ARM
elsif ($magicheader == 0xcefaedfe)
{
	print "Found a Mach-O i386 only binary!\n";
	$baseaddresses{'x86'} = 0x0;
	$target = "x86";
}
# ppc
elsif ($magicheader == 0xfeedface)
{
	print "Found a Mach-O PPC only binary!\n";
	$baseaddresses{'ppc'} = 0x0;
	$target = "ppc";
}
# x64
elsif ($magicheader == 0xcffaedfe)
{
    print "Found a Mach-O x86_64 only binary!\n";
    $baseaddresses{'x64'} = 0x0;
    $target = "x64";
}

# /usr/include/mach-o/loader.h
#struct mach_header 
#{ 
#    uint32_t magic; 
#    cpu_type_t cputype; 
#    cpu_subtype_t cpusubtype; 
#    uint32_t filetype; 
#    uint32_t ncmds; 
#    uint32_t sizeofcmds; 
#    uint32_t flags; 
#}; 
# Total Size: 28 bytes

# interactive mode
if ($mode == 0)
{
	printf("Available architectures in this binary are: ");
	foreach $cpu (keys %baseaddresses)
	{
		printf("%s ", $cpu);
	}
	printf("\n");
	printf("Please choose architecture to calculate offset for: ");
	$userarch = <STDIN>;
	chomp($userarch);
	printf("Please input the desired offset: ");
	$useroffset = <STDIN>;
	chomp($useroffset);
	$myoffset = hex($useroffset);
	$foundcpu = 1;
	$target = $userarch;
	$targetbaseaddress = $baseaddresses{$userarch};
}
elsif ($mode == 1)
{
	foreach $cpu (keys %baseaddresses)
	{
		printf("%s base address: 0x%x\n", $cpu, $baseaddresses{$cpu}) if $debug;
		if ($target eq $cpu) 
		{ 
			$targetbaseaddress = $baseaddresses{$cpu};
			$foundcpu = 1;
		}
	}
}

if ($foundcpu != 1)
{
 printf("\nERROR! Requested architecture \"$target\" doesn't exist in this binary!\n");
 printf("Available architectures are: ");
	foreach $cpu (keys %baseaddresses)
	{
		printf("%s ", $cpu);
	}
 printf("\n");
 exit(1);
}

printf("Reading Mach Header with base address of %x\n", $targetbaseaddress) if $debug;
sysseek(FILE, $targetbaseaddress, 0);
if ($target eq "x86" || $target eq "ppc" || $target =~ /arm/)
{
	sysread(FILE, $buffer, 28);
	# use L in unpack because it's exactly 32bits long (that's what we want!)
	# PPC is big-endian so unpack template must be different! very important ;)
	($magic, $cputype, $cpusubtype, $filetype, $ncmds, $sizeofcmds, $flags) = unpack("LLLLLLL", $buffer) if ($target eq "x86" || $target =~ /arm/);
	($magic, $cputype, $cpusubtype, $filetype, $ncmds, $sizeofcmds, $flags) = unpack("NNNNNNN", $buffer) if ($target eq "ppc");
}
elsif ($target eq "x64")
{
 	sysread(FILE, $buffer, 32);
	($magic, $cputype, $cpusubtype, $filetype, $ncmds, $sizeofcmds, $flags, $reserved) = unpack("LLLLLLLL", $buffer);
}
else
{
	printf("\nERROR while reading mach header!\n");
	exit(1);
}
	
print("\nDebug Information\n-----------------\n") if $debug;
printf("Magic number: %x\n", $magic) if $debug;
printf("Cpu type: %d, subtype is: %d\n", $cputype, $cpusubtype) if $debug;
printf("Filetype: %x\n", $filetype) if $debug;
printf("Number of commands: %d\n", $ncmds) if $debug;
printf("Size of commands: 0x%x\n", $sizeofcmds) if $debug;
printf("Flags: %x\n", $flags) if $debug;
printf("Target architecture: %s\n", $target) if $debug;

#struct load_command 
#{
#    uint32_t cmd; 
#    uint32_t cmdsize; 
#}; 
# Total size: 8 bytes
# process all load commands
  for ($i=0; $i < $ncmds; $i++)
  {
    printf("Processing command nr# %d\n", $i) if $debug;
  	# read each load_command where we get cmd number and total size for it
  	$initialposition = sysseek(FILE, 0, 1);
  	sysread(FILE, $buffer, 8);
  	($cmd, $cmdsize) = unpack("LL", $buffer) if ($target eq "x86" || $target eq "x64" || $target =~ /arm/);
  	($cmd, $cmdsize) = unpack("NN", $buffer) if ($target eq "ppc");
    $table[$i]->{'position'} = $initialposition;
	$table[$i]->{'cmd'} = $cmd;
	$table[$i]->{'cmdsize'} = $cmdsize;	
	# move to the next load command. we can find it by adding the previous load command size minus 8 (because we have read 8 bytes from the previous load command)
	$seekposition = sysseek(FILE, $initialposition+$cmdsize, 0);
  }

  # now let's find our __text,__TEXT section inside a load command
  foreach (@table)
  {
    printf("Looking at cmd %d\n", $_->{'cmd'}) if $debug ;
  	if ($_->{'cmd'} == 1 || $_->{'cmd'} == 0x19)
  	{
  		print("Searching for __text,__TEXT section at position: $_->{'position'}\n") if $debug;
  		# we know it's a LC_SEGMENT so we must read it and see if we can find out __TEXT segment and __text,__TEXT section
  		# skip cmd and cmdsize since we already have them
  		sysseek(FILE, $_->{'position'}+8, 0);
		#struct segment_command 
		#{ 
    	#	uint32_t cmd; 
    	#	uint32_t cmdsize; 
    	#	char segname[16]; 
		#   uint32_t vmaddr; 
		#   uint32_t vmsize; 
		#   uint32_t fileoff; 
		#   uint32_t filesize; 
		#   vm_prot_t maxprot; 
		#   vm_prot_t initprot; 
		#   uint32_t nsects; 
		#   uint32_t flags; 
		#}; 
		# Total Size: 48 bytes
		if ($target eq "x86" || $target eq "ppc" || $target =~ /arm/)
		{
	  		sysread(FILE, $buffer, 48);
  			($segname, $vmaddr, $vmsize, $fileoff, $filesize, $maxprot, $initprot, $nsects, $flags) = unpack("Z16NNNNNNLN", $buffer) if ($target eq "x86" || $target =~/arm/);
  			($segname, $vmaddr, $vmsize, $fileoff, $filesize, $maxprot, $initprot, $nsects, $flags) = unpack("Z16NNNNNNNN", $buffer) if ($target eq "ppc");
  		}
		elsif ($target eq "x64")
		{
  			sysread(FILE, $buffer, 64);
  			($segname, $vmaddr, $vmsize, $fileoff, $filesize, $maxprot, $initprot, $nsects, $flags) = unpack("Z16QQQQLLLL", $buffer) if ($target eq "x64");
  		}
  		else
  		{
  			printf("\nERROR!\n");
  			exit(1);
  		}
  		
  		printf("Segment Name: %s Number of sections: %i \n", $segname, $nsects) if $debug;
  		$currentposition = sysseek(FILE, 0,1);
  		# we are interested in further reading if the number of sections is more than 1.
  		if ($nsects > 0)
  		{
  			for ($x=0; $x < $nsects; $x++)
  			{
	  			#struct section 
				#{ 
    			#	char sectname[16]; 
    			#	char segname[16]; 
				#   uint32_t addr; 
				#   uint32_t size; 
				#   uint32_t offset; 
				#   uint32_t align; 
				#   uint32_t reloff; 
				#   uint32_t nreloc; 
				#   uint32_t flags; 
				#   uint32_t reserved1; 
				#   uint32_t reserved2; 
				#}; 
			    # Total size: 16 + 16 + 9*4 = 68 bytes
			    # read sectname, segname, addr, size, offset
				if ($target eq "x86" || $target eq "ppc" || $target =~ /arm/)
				{	    
			    	sysread(FILE, $buffer, 68);
			    	($sectname, $segname, $addr, $size, $offset) = unpack("Z16Z16VVV", $buffer) if ($target eq "x86" || $target =~/arm/);
			    	($sectname, $segname, $addr, $size, $offset) = unpack("Z16Z16NNN", $buffer) if ($target eq "ppc");
				}
				elsif ($target eq "x64")
				{
			    	sysread(FILE, $buffer, 80);
			    	($sectname, $segname, $addr, $size, $offset, $align, $reloff, $nreloc, $flags, $reserved1, $reserved2, $reserved3) = unpack("Z16Z16QQLLLLLLLL", $buffer) if ($target eq "x64");
			    }
		    	printf("Sectname: %s Segname: %s Offset: %x\n", $sectname, $segname, $offset) if $debug;
		    	# store the information we need to calculate the correct offset
		    	$goodoffset = $offset if ($sectname eq "__text" && $segname eq "__TEXT");
		    	$goodvmaddr = $addr if ($sectname eq "__text" && $segname eq "__TEXT");
		    	$goodsize = $size if ($sectname eq "__text" && $segname eq "__TEXT");    	
  			}
  		}
  		print "\n" if $debug;
  	}
  }
   
printf("CPU base address: 0x%x Goodoffset: 0x%x MyOffset: 0x%x Goodvmaddr: 0x%x\n", $baseaddresses->{'x86'}, $goodoffset, $myoffset, $goodvmaddr) if ($debug && $target eq "x86");
printf("CPU base address: 0x%x Goodoffset: 0x%x MyOffset: 0x%x Goodvmaddr: 0x%x\n", $baseaddresses->{'x86_64'}, $goodoffset, $myoffset, $goodvmaddr) if ($debug && $target eq "x64");
printf("CPU base address: 0x%x Goodoffset: 0x%x MyOffset: 0x%x Goodvmaddr: 0x%x\n", $baseaddresses->{'ppc'}, $goodoffset, $myoffset, $goodvmaddr) if ($debug && $target eq "ppc");
# check if input offset is valid - must be inside the __text segment
if ($myoffset < $goodvmaddr || $myoffset > $goodvmaddr+$goodsize)
{
	print "\nERROR: Your offset is outside code region\n";
	printf("Valid code region is: 0x%x - 0x%x\n", $goodvmaddr, $goodvmaddr+$goodsize);
	exit(1);
}
# calculate the offset we want
$patchedoffset = $targetbaseaddress + $goodoffset + $myoffset - $goodvmaddr;
# and print it !
printf("\nReal offset to be patched: 0x%x\n\n", $patchedoffset);
# end of story!
close(FILE);
