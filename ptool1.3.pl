#!/usr/bin/perl
#
# ptool 
# This program will read and give some information about mach-o files. Kind of more complete otool -l
#
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
# Version 1.2: Fixed lame bug in sections offset display (only the first one was correct)
#			   Added descriptions for section type
#
# Version 1.3: Add ARM support for iOS binaries and add options to display only LC_UNIXTHREAD and LC_ENCRYPTION_INFO segments
#              Support to edit entry points in all binaries (option -e)
#
# TODO: allow to process only one kind of command ?
# 		calculate offset to patch (integrate offset.pl ?)
#		dumper
#		display only what we want, sections for example

my $VERSION = "1.3";
# change me to 1 to have debug messages
my $debug = 0;

#use strict;
# using () so ctime isn't exported else it will conflict with Time::localtime and maybe others. perldoc POSIX
use POSIX();
# for ctime conversions
use Time::localtime;
# for underlines and bolds
use Term::Cap;

my ($normal, $bold, $under, $endu, $t);
my $termios = new POSIX::Termios; $termios->getattr;
my $ospeed = $termios->getospeed;
my $t = Tgetent Term::Cap { TERM => undef, OSPEED => $ospeed };
($normal, $bold, $under, $endu) = map { $t->Tputs($_,1) } qw/me md us ue/;

# command line options
use Getopt::Std;
# Define options
getopts("df:H:hpf:t:e:l:i:a:r:uc", \%arg);
# Set option defaults
$arg{h} = 0 unless $arg{h};
$arg{a} = "" unless $arg{a}; 
$arg{r} = "" unless $arg{r};
$arg{e} = "" unless $arg{e};
$arg{u} = 0 unless $arg{u};
$arg{c} = 0 unless $arg{c};

# definitions
my %table;
my $buffer = "";

# from /usr/include/mach-o/loader.h
my %filetypedesc = ( 1=>"MH_OBJECT" , 2=>"MH_EXECUTE", 3=>"MH_FVMLIB", 4=>"MH_CORE", 5=>"MH_PRELOAD", 6=>"MH_DYLIB", 7=>"MH_DYLINKER", 8=>"MH_BUNDLE", 9=>"MH_DYLIB_STUB", 
					10=>"MH_DSYM", 11=>"MH_KEXT_BUNDLE");

# from include/mach/machine.h
my %cputypedesc = ( 7=>"x86", 12=>"ARM", 18=>"PowerPC", 16777223=>"x86-64", 16777234=>"PowerPC64");

# from /usr/include/mach-o/loader.h
my %cmdtypedesc = ( 0x1=>"LC_SEGMENT", 0x2=>"LC_SYMTAB", 0x3=>"LC_SYMSEG", 0x4=>"LC_THREAD", 0x5=>"LC_UNIXTHREAD", 0x6=>"LC_LOADFVMLIB", 0x7=>"LC_IDFVMLIB",
					0x8=>"LC_IDENT", 0x9=>"LC_FVMFILE", 0xa=>"LC_PREPAGE", 0xb=>"LC_DYSYMTAB", 0xc=>"LC_LOAD_DYLIB", 0xd=>"LC_ID_DYLIB", 0xe=>"LC_LOAD_DYLINKER",
					0xf=>"LC_ID_DYLINKER", 0x10=>"LC_PREBOUND_DYLIB", 0x11=>"LC_ROUTINES", 0x12=>"LC_SUB_FRAMEWORK", 0x13=>"LC_SUB_UMBRELLA", 0x14=>"LC_SUB_CLIENT",
					0x15=>"LC_SUB_LIBRARY", 0x16=>"LC_TWOLEVEL_HINTS", 0x17=>"LC_PREBIND_CKSUM", 0x80000018=>"LC_LOAD_WEAK_DYLIB", 0x19=>"LC_SEGMENT_64",
					0x1a=>"LC_ROUTINES_64", 0x1b=>"LC_UUID", 0x8000001c=>"LC_RPATH", 0x1d=>"LC_CODE_SIGNATURE", 0x1e=>"LC_SEGMENT_SPLIT_INFO",
					0x8000001f=>"LC_REEXPORT_DYLIB", 0x20=>"LC_LAZY_LOAD_DYLIB", 0x21=>"LC_ENCRYPTION_INFO", 0x22=>"LC_DYLD_INFO", 0x80000022=>"LC_DYLD_INFO_ONLY",
					0x80000023=>"LC_LOAD_UPWARD_DYLIB");

my %sectiontypeconstants = (0x0=>"S_REGULAR", 0x1=>"S_ZEROFILL", 0x2=>"S_CSTRING_LITERALS", 0x3=>"S_4BYTE_LITERALS", 0x4=>"S_8BYTE_LITERALS", 0x5=>"S_LITERAL_POINTERS",
							 0x6=>"S_NON_LAZY_SYMBOL_POINTERS", 0x7=>"S_LAZY_SYMBOL_POINTERS", 0x8=>"S_SYMBOL_STUBS", 0x9=>"S_MOD_INIT_FUNC_POINTERS",
							 0xa=>"S_MOD_TERM_FUNC_POINTERS", 0xb=>"S_COALESCED", 0xc=>"S_GB_ZEROFILL", 0xd=>"S_INTERPOSING", 0xe=>"S_16BYTE_LITERALS",
							 0xf=>"S_DTRACE_DOF", 0x10=>"S_LAZY_DYLIB_SYMBOL_POINTERS", 0x11=>"S_THREAD_LOCAL_REGULAR", 0x12=>"S_THREAD_LOCAL_ZEROFILL",
							 0x13=>"S_THREAD_LOCAL_VARIABLES", 0x14=>"S_THREAD_LOCAL_VARIABLE_POINTERS", 0x15=>"S_THREAD_LOCAL_INIT_FUNCTION_POINTERS");
my $info = <<INFO;
ptool v$VERSION
......................................................
(c) 2011 fG! - http://reverse.put.as - reverse\@put.as

Usage: $0 [-a arch] [-e new entrypoint] [-u] [-c] <file>

Where:
<file>   = File to read header from
[-a arch]   = Obtain info only related to this architecture (if available): x86, x86_64, ppc, arm, armv6, armv7
[-e new entrypoint] = New entrypoint to modify
[-u] = show only LC_UNIXTHREAD load command (to see entrypoint)
[-c] = show only LC_ENCRYPTION_INFO load command (can be combined with -u option)

Example for x86:
$0 -a x86 /bin/ls

Example for PPC:
$0 -a ppc /bin/ls

Example for modifying entrypoint in x86:
$0 -a x86 -e 0x1234 /bin/ls

Example for showing only the LC_UNIXTHREAD in ARMv7:
$0 -a armv7 -u /bin/ls

INFO

my $header = <<HEADER;
ptool v$VERSION
......................................................
(c) 2011 fG! - http://reverse.put.as - reverse\@put.as

HEADER

sub help
{
	print $info;
	exit 1;
}

if (!defined($ARGV[0]) || $arg{i} == 1)
{
	help();
}

# because options not processed by Getopts stay in @ARGV
my $filetoopen = $ARGV[0];
if (! -e $filetoopen)
{
	print $header;
	print "ERROR: Can't access file $filetoopen !\n";
	exit(1);
}

# architecture to read specific info from
#my $target = lc($ARGV[1]);
my $target = $arg{a};

# offset to analyse
my $researchoffset = $arg{r};

# create filehandle
# if we want to edit open read/write
if ($arg{e})
{
	open(FILE,"+<$filetoopen") or die("ERROR: Can't open $filetoopen in write mode\n");	
}
# else just read
else
{
	open(FILE,"<$filetoopen") or die("ERROR: Can't open $filetoopen in read mode\n");
}

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
# if it's a fat binary we need to find where the i386 binary is
my ($i, @fatinfo, $x86baseaddress, $ppcbaseaddress, $x86_64baseaddress, $armbaseaddress);

# TODO: VERIFY IF THE REQUESTED ARCHITECTURE EXISTS IN THE BINARY
if ($magicheader == 0xcafebabe)
{

	my $fatbinary = 1;
	printf("Magic Header: 0x%x  [offset: 0x%08x]\n", $magicheader, 0);
	# it's rather safe (but still incorrect) to assume there is a i386 and PPC binary inside the fat binary.
	# still incorrect because it could have a x86 and x86_64 and no PPC... I can live with it for now ;)
	printf("Found a Mach-O fat binary with %d architectures!  [offset: 0x%08x]\n", $nfat_arch, 4);
	print "Finding available architectures base address...\n" if $debug;
	#struct fat_arch @ /usr/include/mach-o/fat.h 
	#{ 
    #	cpu_type_t cputype; 
    #	cpu_subtype_t cpusubtype; 
    #	uint32_t offset; 
    #	uint32_t size; 
    #	uint32_t align; 
	#}; 
	# Total Size: 20 bytes
	my $initialposition = sysseek(FILE, 0, 1);
	# read info from all available binaries inside
	for ($i=0; $i < $nfat_arch; $i++)
	{
		sysread(FILE, $buffer, 20);
		($fatinfo[$i]->{'cputype'}, $fatinfo[$i]->{'cpusubtype'}, $fatinfo[$i]->{'offset'}, $fatinfo[$i]->{'size'}, $fatinfo[$i]->{'align'}) = unpack("NNNNN", $buffer);
		# x86
		if ($fatinfo[$i]->{'cputype'} == 7) { $baseaddresses{'x86'} = $fatinfo[$i]->{'offset'}; }
		# PPC
		elsif ($fatinfo[$i]->{'cputype'} == 18) { $baseaddresses{'ppc'} = $fatinfo[$i]->{'offset'}; }
		# x86_64
		elsif ($fatinfo[$i]->{'cputype'} == 16777223) { $baseaddresses{'x64'} = $fatinfo[$i]->{'offset'}; }
		# ARM_ALL
		elsif ($fatinfo[$i]->{'cputype'} == 12 && $fatinfo[$i]->{'cpusubtype'} == 0x0) { $baseaddresses{'arm'} = $fatinfo[$i]->{'offset'}; }
		# ARM_V6
		elsif ($fatinfo[$i]->{'cputype'} == 12 && $fatinfo[$i]->{'cpusubtype'} == 0x6) { $baseaddresses{'armv6'} = $fatinfo[$i]->{'offset'}; }
		# ARM_V7
		elsif ($fatinfo[$i]->{'cputype'} == 12 && $fatinfo[$i]->{'cpusubtype'} == 0x9) { $baseaddresses{'armv7'} = $fatinfo[$i]->{'offset'}; }
		
	}
	printf("Intel x86 base address: 0x%08x\n", $baseaddresses{'x86'}) if $baseaddresses{'x86'};
	printf("Intel x86_64 base address: 0x%08x\n", $baseaddresses{'x64'}) if $baseaddresses{'x64'};
	printf("PPC base address: 0x%08x\n", $baseaddresses{'ppc'}) if $baseaddresses{'ppc'};
	printf("ARM_ALL base address: 0x%08x\n", $baseaddresses{'arm'}) if $baseaddresses{'arm'};
	printf("ARM_V6 base address: 0x%08x\n", $baseaddresses{'armv6'}) if $baseaddresses{'armv6'};
	printf("ARM_V7 base address: 0x%08x\n", $baseaddresses{'armv7'}) if $baseaddresses{'armv7'};
#	$targetbaseaddress = $x86baseaddress if ($target eq "i386");
#	$targetbaseaddress = $ppcbaseaddress if ($target eq "ppc");
# if it's a single cpu binary then base address is 0
}
elsif ($magicheader == 0xcefaedfe)
{
	print "Found a Mach-O x86 (or ARM) only binary!\n" if $debug;
	$baseaddresses{'x86'} = 0x0;
	$baseaddresses{'arm'} = 0x0;
	$baseaddresses{'armv6'} = 0x0;
	$baseaddresses{'armv7'} = 0x0;
	# it can be x86 or arm, we need to detect which one later
	$target = "x86";
# FIXME - requires -a to be specified if implemented like this
#	if ($target ne $arg{a}) { print "ERROR: Specified architecture $arg{a} not available in this binary\n"; exit(1)};
}
elsif ($magicheader == 0xfeedface)
{
	print "Found a Mach-O PPC only binary!\n" if $debug;
	$baseaddresses{'ppc'} = 0x0;
	$target = "ppc";
}
elsif ($magicheader == 0xcffaedfe)
{
    print "Found a Mach-O x86_64 only binary!\n" if $debug;
    $baseaddresses{'x64'} = 0x0;
    $target = "x86_64";
}

# for 32bits
#struct mach_header @ /usr/include/mach-o/loader.h
#{ 
#        uint32_t        magic;          /* mach magic number identifier */
#        cpu_type_t      cputype;        /* cpu specifier */
#        cpu_subtype_t   cpusubtype;     /* machine specifier */
#        uint32_t        filetype;       /* type of file */
#        uint32_t        ncmds;          /* number of load commands */
#        uint32_t        sizeofcmds;     /* the size of all the load commands */
#        uint32_t        flags;          /* flags */
#}; 
# Total Size: 28 bytes

# for 64bits
#struct mach_header @ /usr/include/mach-o/loader.h
#{ 
#        uint32_t        magic;          /* mach magic number identifier */
#        cpu_type_t      cputype;        /* cpu specifier */
#        cpu_subtype_t   cpusubtype;     /* machine specifier */
#        uint32_t        filetype;       /* type of file */
#        uint32_t        ncmds;          /* number of load commands */
#        uint32_t        sizeofcmds;     /* the size of all the load commands */
#        uint32_t        flags;          /* flags */
#        uint32_t        reserved;       /* reserved */
#};
# Total Size: 32 bytes

# if there is a $target set, then we just read that architecture, else we should read the number of archs specified by $nfat_arch
# read a single arch
my $targetbaseaddress;

if ($target)
{
	# 32 bits
	if ($target eq "x86" || $target eq "ppc" || $target =~ /arm/)
	{
		# this will only apply if we have a fat binary
		# in non-fat binaries we need to distinguish between x86 and arm via the cputype
		$targetbaseaddress = $baseaddresses{'x86'} if ($target eq "x86");
		$targetbaseaddress = $baseaddresses{'arm'} if ($target eq "arm");
		$targetbaseaddress = $baseaddresses{'armv6'} if ($target eq "armv6");
		$targetbaseaddress = $baseaddresses{'armv7'} if ($target eq "armv7");
		$targetbaseaddress = $baseaddresses{'ppc'} if ($target eq "ppc");
		
		printf("DEBUG: Reading the header info...\n") if $debug;
		sysseek(FILE, $targetbaseaddress, 0);
		sysread(FILE, $buffer, 28);
		# use L in unpack because it's exactly 32bits long (that's what we want!)
		# PPC is big-endian so unpack template must be different! very important ;)
		($magic, $cputype, $cpusubtype, $filetype, $ncmds, $sizeofcmds, $flags) = unpack("LLLLLLL", $buffer) if ($target eq "x86" || $target =~ /arm/);
		($magic, $cputype, $cpusubtype, $filetype, $ncmds, $sizeofcmds, $flags) = unpack("NNNNNNN", $buffer) if ($target eq "ppc");
		# set $target variable to the correct architecture
		if ($cputype == 12 && cpusubtype == 0x0)
		{
			$target = "arm";
		}
		elsif ($cputype == 12 && cpusubtype == 0x6)
		{
			$target = "armv6";
		}
		elsif ($cputype == 12 && cpusubtype == 0x9)
		{
			$target = "armv7";
		}
		elsif ($cputype == 7)
		{
			$target = "x86";
		}
		printf("DEBUG: Printing mach header info...\n") if $debug;
		print_mach_header($magic, $cputype, $cpusubtype, $filetype, $ncmds, $sizeofcmds, $flags, 0,$targetbaseaddress,$target);
		printf("DEBUG: Processing load commands...\n") if $debug;
		process_load_commands($ncmds, $targetbaseaddress, $target);
	}
	# and 64 bits
	if ($target eq "x86_64")
	{
		$targetbaseaddress = $baseaddresses{'x64'};
		printf("DEBUG: Reading the header info...\n") if $debug;
		sysseek(FILE, $targetbaseaddress, 0);
		sysread(FILE, $buffer, 32);
		# use L in unpack because it's exactly 32bits long (that's what we want!)
		($magic, $cputype, $cpusubtype, $filetype, $ncmds, $sizeofcmds, $flags, $reserved) = unpack("LLLLLLLL", $buffer);
		printf("DEBUG: Printing mach header info...\n") if $debug;
		print_mach_header($magic, $cputype, $cpusubtype, $filetype, $ncmds, $sizeofcmds, $flags, $reserved,$targetbaseaddress,$target);
		printf("DEBUG: Processing load commands...\n") if $debug;
		process_load_commands($ncmds, $targetbaseaddress, $target);
	}
}
# read all archs - only makes sense if we have a fat binary
else
{
# $fatinfo has all the information that we need
	for ($i=0; $i < $nfat_arch; $i++)
	{
		# x86
		if ($fatinfo[$i]->{'cputype'} == 7)
		{
			my $target = "x86";
			$targetbaseaddress = $baseaddresses{'x86'};
			printf("DEBUG: Reading the header info...\n") if $debug;
			sysseek(FILE, $targetbaseaddress, 0);
			sysread(FILE, $buffer, 28);
			($magic, $cputype, $cpusubtype, $filetype, $ncmds, $sizeofcmds, $flags) = unpack("LLLLLLL", $buffer);
			printf("DEBUG: Printing mach header info...\n") if $debug;
			print_mach_header($magic, $cputype, $cpusubtype, $filetype, $ncmds, $sizeofcmds, $flags, 0,$targetbaseaddress,$target);
			printf("DEBUG: Processing load commands...\n") if $debug;
			process_load_commands($ncmds, $targetbaseaddress, $target);
		};
		# ARM
		if ($fatinfo[$i]->{'cputype'} == 12)
		{
		    if ($fatinfo[$i]->{'cpusubtype'} == 0x0)
		    {
			    $target = "arm";
			    $targetbaseaddress = $baseaddresses{'arm'};
			}
			elsif ($fatinfo[$i]->{'cpusubtype'} == 0x6)
		    {
			    $target = "armv6";
			    $targetbaseaddress = $baseaddresses{'armv6'};
			} 
			elsif ($fatinfo[$i]->{'cpusubtype'} == 0x9)
		    {
			    $target = "armv7";
			    $targetbaseaddress = $baseaddresses{'armv7'};
			} 
			printf("DEBUG: Reading the header info...\n") if $debug;
			sysseek(FILE, $targetbaseaddress, 0);
			sysread(FILE, $buffer, 28);
			($magic, $cputype, $cpusubtype, $filetype, $ncmds, $sizeofcmds, $flags) = unpack("LLLLLLL", $buffer);
			printf("DEBUG: Printing mach header info...\n") if $debug;
			print_mach_header($magic, $cputype, $cpusubtype, $filetype, $ncmds, $sizeofcmds, $flags, 0,$targetbaseaddress,$target);
			printf("DEBUG: Processing load commands...\n") if $debug;
			process_load_commands($ncmds, $targetbaseaddress, $target);
		};		
		# PPC
		if ($fatinfo[$i]->{'cputype'} == 18)
		{
			my $target = "ppc";
			$targetbaseaddress = $baseaddresses{'ppc'};
			printf("DEBUG: Reading the header info...\n") if $debug;
			sysseek(FILE, $targetbaseaddress, 0);
			sysread(FILE, $buffer, 28);
			($magic, $cputype, $cpusubtype, $filetype, $ncmds, $sizeofcmds, $flags) = unpack("NNNNNNN", $buffer);
			printf("DEBUG: Printing mach header info...\n") if $debug;
			print_mach_header($magic, $cputype, $cpusubtype, $filetype, $ncmds, $sizeofcmds, $flags, 0,$targetbaseaddress,$target);	
			printf("DEBUG: Processing load commands...\n") if $debug;
			process_load_commands($ncmds, $targetbaseaddress, $target);
		};
		# x86_64
		if ($fatinfo[$i]->{'cputype'} == 16777223) 
		{
			my $target = "x86_64";
			$targetbaseaddress = $baseaddresses{'x64'};
			printf("DEBUG: Reading the header info...\n") if $debug;
			sysseek(FILE, $targetbaseaddress, 0);
			sysread(FILE, $buffer, 28);
			($magic, $cputype, $cpusubtype, $filetype, $ncmds, $sizeofcmds, $flags, $reserved) = unpack("LLLLLLLL", $buffer);
			printf("DEBUG: Printing mach header info...\n") if $debug;
			print_mach_header($magic, $cputype, $cpusubtype, $filetype, $ncmds, $sizeofcmds, $flags, $reserved,$targetbaseaddress,$target);
			printf("DEBUG: Processing load commands...\n") if $debug;
			process_load_commands($ncmds, $targetbaseaddress, $target);
		};
	}
}

# end of story!
close(FILE);

# this will be common to all architectures
sub print_mach_header
{
		my ($magic, $cputype, $cpusubtype, $filetype, $ncmds, $sizeofcmds, $flags, $reserved,$targetbaseaddress,$target) = @_;
		print("\nMach_header Information\n-----------------------\n");
		printf("${bold}Target architecture:${normal} %s\n", $target);
		printf("${bold}Magic number:${normal} 0x%08x  [offset: 0x%08x]\n", $magic, $targetbaseaddress);
		printf("${bold}Cpu type:${normal} %d - %s  [offset: 0x%08x]\n", $cputype, $cputypedesc{$cputype}, $targetbaseaddress+4);
		printf("${bold}Cpu subtype:${normal} %x  [offset: 0x%08x]\n", $cpusubtype, $targetbaseaddress+8);
		printf("${bold}Filetype:${normal} 0x%2x (%s)  [offset: 0x%08x]\n", $filetype, $filetypedesc{$filetype}, $targetbaseaddress+12);
		printf("${bold}Number of commands:${normal} %d (0x%x)  [offset: 0x%08x]\n", $ncmds, $ncmds, $targetbaseaddress+16);
		printf("${bold}Size of commands:${normal} %d bytes (0x%x)  [offset: 0x%08x]\n", $sizeofcmds, $sizeofcmds, $targetbaseaddress+20);
		printf("${bold}Flags:${normal} 0x%08x  [offset: 0x%08x]\n", $flags, $targetbaseaddress+24);
		if ($target eq "x86_64")
		{
			printf("${bold}Reserved field:${normal} 0x%08x  [offset: 0x%08x]\n", $reserved, $targetbaseaddress+28);
		}		
}

#struct load_command @ /usr/include/mach-o/loader.h
#{
#    uint32_t cmd; 
#    uint32_t cmdsize; 
#}; 
# Total size: 8 bytes

# we need the baseaddress for each architecture so we can position and read commands
sub process_load_commands
{
  my $i;
  my ($ncmds, $targetbaseaddress, $target) = @_;
  # put us in the correct file position for the architecture
  $initialposition = sysseek(FILE, $targetbaseaddress+28, 0) if ($target eq "x86" || $target eq "ppc" || $target =~ /arm/);
  $initialposition = sysseek(FILE, $targetbaseaddress+32, 0) if ($target eq "x86_64");
  for ($i=0; $i < $ncmds; $i++)
  {
	my $buffer = "";
  	# read each load_command where we get cmd number and total size for it
  	$initialposition = sysseek(FILE, 0, 1);
  	sysread(FILE, $buffer, 8);
  	($cmd, $cmdsize) = unpack("LL", $buffer) if ($target eq "x86" || $target eq "x86_64" || $target =~ /arm/);
  	($cmd, $cmdsize) = unpack("NN", $buffer) if ($target eq "ppc");
    $table[$i]->{'position'} = $initialposition;
	$table[$i]->{'cmd'} = $cmd;
	$table[$i]->{'cmdsize'} = $cmdsize;	
	# move to the next load command. we can find it by adding the previous load command size minus 8 (because we have read 8 bytes from the previous load command)
	$seekposition = sysseek(FILE, $initialposition+$cmdsize, 0);
  }
  
  $counter = 0;

# if we are editing the entrypoint
  if ($arg{e})
  {
        if (!$arg{a})
        {  
            printf("\nERROR: You must specify the architecture to modify EIP!\n\n");
            exit(1);
        }
		foreach (@table)
		{
			if ($_->{'cmd'} == 0x4 || $_->{'cmd'} == 0x5)
			{
			    printf("\n${bold}Modifying EIP...${normal}\n");
				modify_eip($_->{'position'}, $target, $targetbaseaddress, $counter);
			}
			$counter++;
		}
  }
  # process only LC_UNIXTHREAD and/or LC_ENCRYPTION_INFO
  elsif ($arg{u} || $arg{c})
  {
        foreach (@table)
        {
            ### LC_UNIXTHREAD or LC_THREAD
      		if (($_->{'cmd'} == 0x4 || $_->{'cmd'} == 0x5) && $arg{u})
		    { 
        		printf("\n--( LOAD COMMAND #%d )--------------------------[ offset: 0x%08x ]--\n", $counter, $_->{'position'});
       	    	printf("${bold}cmd name:${normal} %s (0x%x)  [offset: 0x%08x]\n", $cmdtypedesc{$_->{'cmd'}}, $_->{'cmd'}, $_->{'position'});
         		printf("${bold}cmd size:${normal} %d bytes (0x%08x)  [offset: 0x%08x]\n", $_->{'cmdsize'}, $_->{'cmdsize'}, $_->{'position'}+4);
			    process_thread_command($_->{'position'}, $target, $targetbaseaddress, $counter);
    		}
 		    ### LC_ENCRYPTION_INFO
    		elsif ($_->{'cmd'} == 0x21 && $arg{c})
	    	{
        		printf("\n--( LOAD COMMAND #%d )--------------------------[ offset: 0x%08x ]--\n", $counter, $_->{'position'});
       	    	printf("${bold}cmd name:${normal} %s (0x%x)  [offset: 0x%08x]\n", $cmdtypedesc{$_->{'cmd'}}, $_->{'cmd'}, $_->{'position'});
         		printf("${bold}cmd size:${normal} %d bytes (0x%08x)  [offset: 0x%08x]\n", $_->{'cmdsize'}, $_->{'cmdsize'}, $_->{'position'}+4);
		    	process_encryption_info_command($_->{'position'}, $target, $targetbaseaddress, $counter);
    		}	
        }
   }
            
# else we are just dumping the information
  else
  {
   foreach (@table) 
   {
		printf("\n--( LOAD COMMAND #%d )--------------------------[ offset: 0x%08x ]--\n", $counter, $_->{'position'});
#  		printf("Load command number: %d  [offset: 0x%08x]\n", $counter, $_->{'position'});
  		printf("${bold}cmd name:${normal} %s (0x%x)  [offset: 0x%08x]\n", $cmdtypedesc{$_->{'cmd'}}, $_->{'cmd'}, $_->{'position'});
  		printf("${bold}cmd size:${normal} %d bytes (0x%08x)  [offset: 0x%08x]\n", $_->{'cmdsize'}, $_->{'cmdsize'}, $_->{'position'}+4);
  		### commands LC_LOADFVMLIB, LC_IDFVMLIB, LC_IDENT and LC_FVMFILE, LC_PREPAGE are obsolete and internal, so they aren't processed (although otool does it)
  		### maybe in a future VERSION
  		# TODO: implement LC_PREBOUND_DYLIB
  		
  		### process LC_SEGMENT and LC_SEGMENT_64 commands
    	if ($_->{'cmd'} == 0x1 || $_->{'cmd'} == 0x19 )
  		{
  			process_lc_segment($_->{'position'}, $target, $targetbaseaddress, $counter);
		}
		### LC_SYMTAB
		if ($_->{'cmd'} == 0x2)
		{
			process_lc_symtab($_->{'position'}, $target, $targetbaseaddress, $counter);
		}
		if ($_->{'cmd'} == 0x3)
		{
			process_symseg_command($_->{'position'}, $target, $targetbaseaddress, $counter);
		}
		### LC_UNIXTHREAD or LC_THREAD
		if ($_->{'cmd'} == 0x4 || $_->{'cmd'} == 0x5)
		{
			process_thread_command($_->{'position'}, $target, $targetbaseaddress, $counter);
		}
		### LC_ROUTINES or LC_ROUTINES_64
		if ($_->{'cmd'} == 0x11 || $_->{'cmd'} == 0x1a)
		{
			process_routines_command($_->{'position'}, $target, $targetbaseaddress, $counter);
		}
		### LC_SUB_FRAMEWORK
		if ($_->{'cmd'} == 0x12)
		{
			process_sub_framework_command($_->{'position'}, $target, $targetbaseaddress, $counter);
		}
		### LC_SUB_UMBRELLA
		if ($_->{'cmd'} == 0x13)
		{
			process_sub_umbrella_command($_->{'position'}, $target, $targetbaseaddress, $counter);
		}
		### LC_SUB_CLIENT
		if ($_->{'cmd'} == 0x14)
		{
			process_sub_client_command($_->{'position'}, $target, $targetbaseaddress, $counter);
		}
		### LC_SUB_LIBRARY
		if ($_->{'cmd'} == 0x15)
		{
			process_sub_library_command($_->{'position'}, $target, $targetbaseaddress, $counter);
		}
		### LC_TWOLEVEL_HINTS
		if ($_->{'cmd'} == 0x16)
		{
			process_twolevel_hints_command($_->{'position'}, $target, $targetbaseaddress, $counter);
		}
		### LC_TWOLEVEL_HINTS
		if ($_->{'cmd'} == 0x17)
		{
			process_prebind_cksum_command($_->{'position'}, $target, $targetbaseaddress, $counter);
		}
		### LC_DYSYMTAB
		if ($_->{'cmd'} == 0xb)
		{
			process_lc_dysymtab($_->{'position'}, $target, $targetbaseaddress, $counter);
		}
		### LC_ID_DYLIB, LC_LOAD_DYLIB, LC_LOAD_WEAK_DYLIB, LC_REEXPORT_DYLIB
		if ($_->{'cmd'} == 0xd || $_->{'cmd'} == 0xc || $_->{'cmd'} == 0x80000018 || $_->{'cmd'} == 0x8000001f)
		{
			process_dylib_command($_->{'position'}, $target, $targetbaseaddress, $counter);
		}
		### LC_ID_DYLINKER or LC_LOAD_DYLINKER
		if ($_->{'cmd'} == 0xf || $_->{'cmd'} == 0xe)
		{
			process_lc_load_dylinker($_->{'position'}, $target, $targetbaseaddress, $counter);
		}
		### LC_UUID
		if ($_->{'cmd'} == 0x1b)
		{
			process_uuid_command($_->{'position'}, $target, $targetbaseaddress, $counter);
		}
		### LC_CODE_SIGNATURE or LC_SEGMENT_SPLIT_INFO
		if ($_->{'cmd'} == 0x1e || $_->{'cmd'} == 0x1d)
		{
			process_linkedit_data_command($_->{'position'}, $target, $targetbaseaddress, $counter);
		}
		### LC_ENCRYPTION_INFO
		if ($_->{'cmd'} == 0x21)
		{
			process_encryption_info_command($_->{'position'}, $target, $targetbaseaddress, $counter);
		}		
		### LC_DYLD_INFO or LC_DYLD_INFO_ONLY
		if ($_->{'cmd'} == 0x22 || $_->{'cmd'} == 0x80000022)
		{
			process_lc_dyld_info($_->{'position'}, $target, $targetbaseaddress, $counter);
		}
		### LC_RPATH
		if ($_->{'cmd'} == 0x8000001c)
		{
			process_rpath_command($_->{'position'}, $target, $targetbaseaddress, $counter);
		}

	  	$counter++;
   }
  }
	
	
}
	


sub process_lc_segment
{
		my $counter, $x;
		my $buffer="";
		my ($position, $target, $targetbaseaddress, $loadcommandnumber) = @_;
  		# we know it's a LC_SEGMENT so we must read it and see if we can find out __TEXT segment and __text,__TEXT section
  		sysseek(FILE, $position+8, 0);
  		
  		# 32 bits
		#struct segment_command @ /usr/include/mach-o/loader.h
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
		# Total Size: 8+48 bytes
		
		# 64 bits
		#struct segment_command_64 { /* for 64-bit architectures */
        #	uint32_t        cmd;            /* LC_SEGMENT_64 */
        #	uint32_t        cmdsize;        /* includes sizeof section_64 structs */
        #	char            segname[16];    /* segment name */
        #	uint64_t        vmaddr;         /* memory address of this segment */
        #	uint64_t        vmsize;         /* memory size of this segment */
        #	uint64_t        fileoff;        /* file offset of this segment */
        #	uint64_t        filesize;       /* amount to map from the file */
        #	vm_prot_t       maxprot;        /* maximum VM protection */
        #	vm_prot_t       initprot;       /* initial VM protection */
        #	uint32_t        nsects;         /* number of sections in segment */
        #	uint32_t        flags;          /* flags */
		#};
		# Total Size: 8+64 bytes
		
  		sysread(FILE, $buffer, 48) if ($target eq "x86" || $target eq "ppc" || $target eq "arm");
  		sysread(FILE, $buffer, 64) if ($target eq "x86_64");
  		
  		($segname, $vmaddr, $vmsize, $fileoff, $filesize, $maxprot, $initprot, $nsects, $flags) = unpack("Z16LLLLLLLL", $buffer) if ($target eq "x86" || $target =~ /arm/);
  		($segname, $vmaddr, $vmsize, $fileoff, $filesize, $maxprot, $initprot, $nsects, $flags) = unpack("Z16NNNNNNNN", $buffer) if ($target eq "ppc");
		($segname, $vmaddr, $vmsize, $fileoff, $filesize, $maxprot, $initprot, $nsects, $flags) = unpack("Z16QQQQLLLL", $buffer) if ($target eq "x86_64");

#  		printf("Segment Name: %s Number of sections: %i \n", $segname, $nsects) if $debug;
		printf("${bold}segment name:${normal} %s  [offset: 0x%08x]\n", $segname, $position+8);
		if ($target eq "x86" || $target eq "ppc" || $target =~ /arm/)
		{
			printf("${bold}memory address:${normal} 0x%08x  [offset: 0x%08x]\n", $vmaddr, $position+=24);
			printf("${bold}memory size:${normal} %d bytes (0x%08x)  [offset: 0x%08x]\n", $vmsize, $vmsize, $position+=4);
			printf("${bold}file offset:${normal} 0x%08x  [offset: 0x%08x]\n", $fileoff, $position+=4);
			printf("${bold}file size:${normal} %d bytes (0x%08x)  [offset: 0x%08x]\n", $filesize, $filesize, $position+=4);
			printf("${bold}max prot:${normal} 0x%08x  [offset: 0x%08x]\n", $maxprot, $position+=4);
			printf("${bold}init prot:${normal} 0x%08x  [offset: 0x%08x]\n", $initprot, $position+=4);
			printf("${bold}number of sections:${normal} %d  [offset: 0x%08x]\n", $nsects, $position+=4);
			# TODO: add descriptions from the include
			printf("${bold}flags:${normal} 0x%x  [offset: 0x%08x]\n", $flags, $position+=4);
		}
		elsif ($target eq "x86_64")
		{
			printf("${bold}memory address:${normal} 0x%016llx  [offset: 0x%08x]\n", $vmaddr, $position+=24);
			printf("${bold}memory size:${normal} %lld bytes (0x%016llx)  [offset: 0x%08x]\n", $vmsize, $vmsize, $position+=8);
			printf("${bold}file offset:${normal} 0x%016llx  [offset: 0x%08x]\n", $fileoff, $position+=8);
			printf("${bold}file size:${normal} %lld bytes (0x%016llx)  [offset: 0x%08x]\n", $filesize, $filesize, $position+=8);
			printf("${bold}max prot:${normal} 0x%08x  [offset: 0x%08x]\n", $maxprot, $position+=8);
			printf("${bold}init prot:${normal} 0x%08x  [offset: 0x%08x]\n", $initprot, $position+=4);
			printf("${bold}number of sections:${normal} %d  [offset: 0x%08x]\n", $nsects, $position+=4);
			# TODO: add descriptions from the include
			printf("${bold}flags:${normal} 0x%x  [offset: 0x%08x]\n", $flags, $position+=4);
		}
				
  		$currentposition = sysseek(FILE, 0,1);
  		# we are interested in further reading if the number of sections is more than 1.
  		if ($nsects > 0)
  		{
			my $counter = 0;
  			for ($x=0; $x < $nsects; $x++)
  			{
  				my $buffer = "";
#	  			printf("[Section %d]\n", $counter);
  			printf("\n--( SECTION #%d )--------------------------( LOAD CMD #%d )--\n", $counter, $loadcommandnumber);

	  			#struct section { /* for 32-bit architectures */
			    #    char            sectname[16];   /* name of this section */
			    #    char            segname[16];    /* segment this section goes in */
			    #    uint32_t        addr;           /* memory address of this section */
			    #    uint32_t        size;           /* size in bytes of this section */
			    #    uint32_t        offset;         /* file offset of this section */
			    #    uint32_t        align;          /* section alignment (power of 2) */
			    #    uint32_t        reloff;         /* file offset of relocation entries */
			    #    uint32_t        nreloc;         /* number of relocation entries */
			    #    uint32_t        flags;          /* flags (section type and attributes)*/
			    #    uint32_t        reserved1;      /* reserved (for offset or index) */
			    #    uint32_t        reserved2;      /* reserved (for count or sizeof) */
				#};
			    # Total size: 16 + 16 + 9*4 = 68 bytes
			    
			    #struct section_64 { /* for 64-bit architectures */
			    #    char            sectname[16];   /* name of this section */
			    #    char            segname[16];    /* segment this section goes in */
			    #    uint64_t        addr;           /* memory address of this section */
			    #    uint64_t        size;           /* size in bytes of this section */
			    #    uint32_t        offset;         /* file offset of this section */
			    #    uint32_t        align;          /* section alignment (power of 2) */
			    #    uint32_t        reloff;         /* file offset of relocation entries */
			    #    uint32_t        nreloc;         /* number of relocation entries */
			    #    uint32_t        flags;          /* flags (section type and attributes)*/
			    #    uint32_t        reserved1;      /* reserved (for offset or index) */
			    #    uint32_t        reserved2;      /* reserved (for count or sizeof) */
			    #    uint32_t        reserved3;      /* reserved */
				#};
				#Total size: 32 + 16 + 8*4 = 80 bytes
				
			    # read sectname, segname, addr, size, offset
		    	sysread(FILE, $buffer, 68) if ($target eq "x86" || $target eq "ppc" || $target =~ /arm/);
		    	sysread(FILE, $buffer, 80) if ($target eq "x86_64");
		    	
		    	($sectname, $segname, $addr, $size, $offset, $align, $reloff, $nreloc, $flags, $reserved1, $reserved2) = unpack("Z16Z16LLLLLLLLL", $buffer) if ($target eq "x86" || $target =~ /arm/);
		    	($sectname, $segname, $addr, $size, $offset, $align, $reloff, $nreloc, $flags, $reserved1, $reserved2) = unpack("Z16Z16NNNNNNNNN", $buffer) if ($target eq "ppc");
		    	($sectname, $segname, $addr, $size, $offset, $align, $reloff, $nreloc, $flags, $reserved1, $reserved2, $reserved3) = unpack("Z16Z16QQLLLLLLLL", $buffer) if ($target eq "x86_64");

				if ($target eq "x86" || $target eq "ppc" || $target =~ /arm/)
				{
					printf("${bold}section name:${normal} %s  [offset: 0x%08x]\n", $sectname, $currentposition);
					printf("${bold}segment name:${normal} %s  [offset: 0x%08x]\n", $segname, $currentposition+=16);
					printf("${bold}memory address:${normal} 0x%08x  [offset: 0x%08x]\n", $addr, $currentposition+=16);
					printf("${bold}section size:${normal} %d bytes (0x%08x)  [offset: 0x%08x]\n", $size, $size, $currentposition+=4);
					printf("${bold}file offset:${normal} 0x%08x ${bold}real file offset:${normal} 0x%08x  [offset: 0x%08x]\n", $offset, $targetbaseaddress+$offset, $currentposition+=4);
					printf("${bold}section alignment:${normal} 2^%d (%d)  [offset: 0x%08x]\n", $align, 2**$align, $currentposition+=4);
					printf("${bold}relocation entries offset:${normal} 0x%08x  [offset: 0x%08x]\n", $reloff, $currentposition+=4);
					printf("${bold}number of relocation entries:${normal} %d  [offset: 0x%08x]\n", nreloc, $currentposition+=4);
					printf("${bold}flags:${normal} 0x%08x  [offset: 0x%08x]\n", $flags, $currentposition+=4);
					printf("${bold}section type:${normal} %s\n", $sectiontypeconstants{$flags & 0xFF});
					# TODO: interpretation of reserved flags
					printf("${bold}reserved1:${normal} 0x%08x  [offset: 0x%08x]\n", $reserved1, $currentposition+=4);
					printf("${bold}reserved2:${normal} 0x%08x  [offset: 0x%08x]\n", $reserved2, $currentposition+=4);
					$currentposition += 4;
				}
				elsif ($target eq "x86_64")
				{
					printf("${bold}section name:${normal} %s  [offset: 0x%08x]\n", $sectname, $currentposition);
					printf("${bold}segment name:${normal} %s  [offset: 0x%08x]\n", $segname, $currentposition+=16);
					printf("${bold}memory address:${normal} 0x%016llx  [offset: 0x%08x]\n", $addr, $currentposition+=16);
					printf("${bold}section size:${normal} %lld bytes (0x%016llx)  [offset: 0x%08x]\n", $size, $size, $currentposition+=8);
					printf("${bold}file offset:${normal} 0x%08x ${bold}real file offset:${normal} 0x%08x  [offset: 0x%08x]\n", $offset, $targetbaseaddress+$offset, $currentposition+=8);
					printf("${bold}section alignment:${normal} 2^%d (%d)  [offset: 0x%08x]\n", $align, 2**$align, $currentposition+=4);
					printf("${bold}relocation entries offset:${normal} 0x%08x  [offset: 0x%08x]\n", $reloff, $currentposition+=4);
					printf("${bold}number of relocation entries:${normal} %d  [offset: 0x%08x]\n", nreloc, $currentposition+=4);
					printf("${bold}flags:${normal} 0x%08x  [offset: 0x%08x]\n", $flags, $currentposition+=4);
					printf("${bold}section type:${normal} %s\n", $sectiontypeconstants{$flags & 0xFF});
					# TODO: interpretation of reserved flags
					printf("${bold}reserved1:${normal} 0x%08x  [offset: 0x%08x]\n", $reserved1, $currentposition+=4);
					printf("${bold}reserved2:${normal} 0x%08x  [offset: 0x%08x]\n", $reserved2, $currentposition+=4);
					printf("${bold}reserved3:${normal} 0x%08x  [offset: 0x%08x]\n", $reserved3, $currentposition+=4);
					$currentposition += 4;
				}
		    	$counter++;
  			}
  		}
}

### LC_SYMTAB
sub process_lc_symtab
{
	my $buffer="";
	my $symoff, $nsyms, $stroff, $strsize;
	my ($position, $target, $targetbaseaddress, $loadcommandnumber) = @_;
	#struct symtab_command {
    #    uint32_t        cmd;            /* LC_SYMTAB */
    #    uint32_t        cmdsize;        /* sizeof(struct symtab_command) */
    #    uint32_t        symoff;         /* symbol table offset */
    #    uint32_t        nsyms;          /* number of symbol table entries */
    #    uint32_t        stroff;         /* string table offset */
    #    uint32_t        strsize;        /* string table size in bytes */
	#};
	# Total Size: 8 + 4*4 = 24 bytes
	sysseek(FILE, $position+8, 0);
	sysread(FILE, $buffer, 16);
  		
	if ($target eq "x86" || $target eq "x86_64" || $target eq "arm") { $unpackstring = "LLLL" } else { $unpackstring = "NNNN" };
	($symoff, $nsyms, $stroff, $strsize) = unpack($unpackstring, $buffer);

	printf("${bold}symbol table offset:${normal} 0x%08x  [offset: 0x%08x]\n", $symoff, $position+=8);
	printf("${bold}number of symtol table entries:${normal} %d  [offset: 0x%08x]\n", $nsyms, $position+=4);
	printf("${bold}string table offset:${normal} 0x%08x  [offset: 0x%08x]\n", $stroff, $position+=4);
	printf("${bold}string table size:${normal} %d bytes 0x%08x  [offset: 0x%08x]\n", $strsize, $strsize, $positon+=4);
}

### LC_DYLD_INFO or LC_DYLD_INFO_ONLY
sub process_lc_dyld_info
{
	my $buffer="";
	my $rebase_off, $rebase_size, $bind_off, $bind_size, $weak_bind_off, $weak_bind_size, $lazy_bind_off, $lazy_bind_size, $export_off, $export_size;
	my ($position, $target, $targetbaseaddress, $loadcommandnumber) = @_;
	#struct dyld_info_command {
	#   uint32_t   cmd;              /* LC_DYLD_INFO or LC_DYLD_INFO_ONLY */
	#   uint32_t   cmdsize;          /* sizeof(struct dyld_info_command) */
	#   uint32_t   rebase_off;      /* file offset to rebase info  */
	#   uint32_t   rebase_size;     /* size of rebase info   */
	#   uint32_t   bind_off;        /* file offset to binding info   */
	#   uint32_t   bind_size;       /* size of binding info  */
	#   uint32_t   weak_bind_off;   /* file offset to weak binding info   */
	#   uint32_t   weak_bind_size;  /* size of weak binding info  */
	#   uint32_t   lazy_bind_off;   /* file offset to lazy binding info */
	#   uint32_t   lazy_bind_size;  /* size of lazy binding infs */
	#   uint32_t   export_off;      /* file offset to lazy binding info */
	#   uint32_t   export_size;     /* size of lazy binding infs */
	#};
	# Total Size: 8 + 10*4 = 48 bytes
	sysseek(FILE, $position+8, 0);
	sysread(FILE, $buffer, 40);
	
	if ($target eq "x86" || $target eq "x86_64" || $target eq "arm") { $unpackstring = "LLLLLLLLLL" } else { $unpackstring = "NNNNNNNNNN" };
	($rebase_off, $rebase_size, $bind_off, $bind_size, $weak_bind_off, $weak_bind_size, $lazy_bind_off, $lazy_bind_size, $export_off, $export_size) = unpack($unpackstring, $buffer);
	
	printf("${bold}rebase offset:${normal} 0x%08x ${bold}real offset:${normal} 0x%08x  [offset: 0x%08x]\n", $rebase_off, $targetbaseaddress+$rebase_off, $position+=8 );
	printf("${bold}rebase size:${normal} %d bytes (0x%08x)  [offset: 0x%08x]\n", $rebase_size, $rebase_size, $positon+=4);
	printf("${bold}binding offset:${normal} 0x%08x ${bold}real offset:${normal} 0x%08x  [offset: 0x%08x]\n", $bind_off, $targetbaseaddress+$bind_off, $position+=4);
	printf("${bold}binding size:${normal} %d bytes (0x%08x)  [offset: 0x%08x]\n", $bind_size, $bind_size, $positon+=4);
	printf("${bold}weak binding offset:${normal} 0x%08x ${bold}real offset:${normal} 0x%08x  [offset: 0x%08x]\n", $weak_bind_off, $targetbaseaddress+$weak_bind_off, $position+=4);
	printf("${bold}weak binding size:${normal} %d bytes (0x%08x)  [offset: 0x%08x]\n", $weak_bind_size, $weak_bind_size, $positon+=4);
	printf("${bold}lazy binding offset:${normal} 0x%08x ${bold}real offset:${normal} 0x%08x  [offset: 0x%08x]\n", $lazy_bind_off, $targetbaseaddress+$lazy_bind_off, $positon+=4);
	printf("${bold}lazy binding size:${normal} %d bytes (0x%08x)  [offset: 0x%08x]\n", $lazy_bind_size, $lazy_bind_size, $positon+=4);
	printf("${bold}export offset:${normal} 0x%08x ${bold}real offset:${normal} 0x%08x  [offset: 0x%08x]\n", $export_off, $targetbaseaddress+$export_off, $positon+=4);
	printf("${bold}export size:${normal} %d bytes (0x%08x)  [offset: 0x%08x]\n", $export_size, $export_size, $positon+=4);
}

### LC_ID_DYLINKER or LC_LOAD_DYLINKER
sub process_lc_load_dylinker
{
	my $buffer="";
	my $cmd, $cmdsize, $offset, $name, $sizetoread;
	my ($position, $target, $targetbaseaddress, $loadcommandnumber) = @_;
	#struct dylinker_command {
	#        uint32_t        cmd;            /* LC_ID_DYLINKER or LC_LOAD_DYLINKER */
	#        uint32_t        cmdsize;        /* includes pathname string */
	#        union lc_str    name;           /* dynamic linker's path name */
	#};
	# Total Size: 8 + variable size string = 
	sysseek(FILE, $position, 0);
	sysread(FILE, $buffer, 12);
	
	if ($target eq "x86" || $target eq "x86_64" || $target eq "arm") { $unpackstring = "LLL" } else { $unpackstring = "NNN" };
	($cmd, $cmdsize, $offset) = unpack($unpackstring, $buffer);
	
	$sizetoread = $cmdsize - 12;
	
	sysseek(FILE, $position+12, 0);
	sysread(FILE, $buffer, $sizetoread);
	
	($name) = unpack("Z$sizetoread", $buffer);
	
	printf("${bold}dynamic linker path name:${normal} %s  [offset: 0x%08x]\n", $name, $position+12 );
}

### LC_DYSYMTAB
sub process_lc_dysymtab
{
	my $buffer="";
	my $ilocalsym, $nlocalsym, $iextdefsym, $nextdefsym, $iundefsym, $nundefsym, $tocoff, $ntoc, $modtaboff, $nmodtab, $extrefsymoff, $nextrefsyms, $indirectsymoff, $nindirectsyms, $extreloff, $nextrel, $locreloff, $nlocrel;
	my ($position, $target, $targetbaseaddress, $loadcommandnumber) = @_;
	#struct dysymtab_command {
	#    uint32_t cmd;       /* LC_DYSYMTAB */
	#    uint32_t cmdsize;   /* sizeof(struct dysymtab_command) */
	#    uint32_t ilocalsym; /* index to local symbols */
	#    uint32_t nlocalsym; /* number of local symbols */
	#	 uint32_t iextdefsym;/* index to externally defined symbols */
	#    uint32_t nextdefsym;/* number of externally defined symbols */
	#    uint32_t iundefsym; /* index to undefined symbols */
	#    uint32_t nundefsym; /* number of undefined symbols */
	#    uint32_t tocoff;    /* file offset to table of contents */
	#    uint32_t ntoc;      /* number of entries in table of contents */
	#    uint32_t modtaboff; /* file offset to module table */
	#    uint32_t nmodtab;   /* number of module table entries */
	#    uint32_t extrefsymoff;      /* offset to referenced symbol table */
	#    uint32_t nextrefsyms;       /* number of referenced symbol table entries */
	#    uint32_t indirectsymoff; /* file offset to the indirect symbol table */
	#    uint32_t nindirectsyms;  /* number of indirect symbol table entries */
	#    uint32_t extreloff; /* offset to external relocation entries */
	#    uint32_t nextrel;   /* number of external relocation entries */
	#    uint32_t locreloff; /* offset to local relocation entries */
	#    uint32_t nlocrel;   /* number of local relocation entries */
	#};
	# Total Size: 8 + 18*4 = 80 bytes

	sysseek(FILE, $position+8, 0);
	sysread(FILE, $buffer, 72);
	
	if ($target eq "x86" || $target eq "x86_64" || $target eq "arm") { $unpackstring = "LLLLLLLLLLLLLLLLLL" } else { $unpackstring = "NNNNNNNNNNNNNNNNNN" };	
	($ilocalsym, $nlocalsym, $iextdefsym, $nextdefsym, $iundefsym, $nundefsym, $tocoff, $ntoc, $modtaboff, $nmodtab, $extrefsymoff, $nextrefsyms, $indirectsymoff, $nindirectsyms, $extreloff, $nextrel, $locreloff, $nlocrel) = unpack($unpackstring, $buffer);

	printf("${bold}index to local symbols:${normal} 0x%08x  [offset: 0x%08x]\n", $ilocalsym , $position+=8 );
	printf("${bold}number of local symbols:${normal} %d  [offset: 0x%08x]\n", $nlocalsym, $position+=4 );
	printf("${bold}index to externally defined symbols:${normal} 0x%08x  [offset: 0x%08x]\n", $iextdefsym, $position+=4 );
	printf("${bold}number of externally defined symbols:${normal} %d  [offset: 0x%08x]\n", $nextdefsym, $position+=4 );
	printf("${bold}index to undefined symbols:${normal} 0x%08x  [offset: 0x%08x]\n", $iundefsym, $position+=4 );
	printf("${bold}number of undefined symbols:${normal} %d  [offset: 0x%08x]\n", $nundefsym, $position+=4 );
	printf("${bold}file offset to table of contents:${normal} 0x%08x  [offset: 0x%08x]\n", $tocoff, $position+=4 );
	printf("${bold}number of entries in toc:${normal} %d  [offset: 0x%08x]\n", $ntoc, $position+=4 );
	printf("${bold}file offset to module table:${normal} 0x%08x  [offset: 0x%08x]\n", $modtaboff, $position+=4 );
	printf("${bold}number of module table entries:${normal} %d  [offset: 0x%08x]\n", $nmodtab, $position+=4 );
	printf("${bold}offset to referenced symbol table:${normal} 0x%08x  [offset: 0x%08x]\n", $extrefsymoff, $position+=4 );
	printf("${bold}number of referenced symbol table entries:${normal} %d  [offset: 0x%08x]\n", $nextrefsyms, $position+=4 );
	printf("${bold}file offset to the indirect symbol table:${normal} 0x%08x  [offset: 0x%08x]\n", $indirectsymoff, $position+=4 );
	printf("${bold}number of indirect symbol table entries:${normal} %d  [offset: 0x%08x]\n", $nindirectsyms, $position+=4 );
	printf("${bold}offset to external relocation entries:${normal} 0x%08x  [offset: 0x%08x]\n", $extreloff, $position+=4 );
	printf("${bold}number of external relocation entries:${normal} %d  [offset: 0x%08x]\n", $nextrel, $position+=4 );
	printf("${bold}offset to local relocation entries:${normal} 0x%08x  [offset: 0x%08x]\n", $locreloff, $position+=4 );
	printf("${bold}number of local relocation entries:${normal} %d  [offset: 0x%08x]\n", $nlocrel, $position+=4 );
}

### LC_ID_DYLIB, LC_LOAD_{,WEAK_}DYLIB
sub process_dylib_command
{
	my $buffer="";
	my $cmd, $cmdsize, $offset, $name, $timestamp, $current_version, $compatibility_version;
	my ($position, $target, $targetbaseaddress, $loadcommandnumber) = @_;
	#struct dylib_command {
	#        uint32_t        cmd;            /* LC_ID_DYLIB, LC_LOAD_{,WEAK_}DYLIB,
	#        uint32_t        cmdsize;        /* includes pathname string */
	#        struct dylib    dylib;          /* the library identification */
	#};
	# Total Size: 8 + 4 + string size + 3*4 
	#struct dylib {
	#    union lc_str  name;                 /* library's path name */
	#    uint32_t timestamp;                 /* library's build time stamp */
	#    uint32_t current_version;           /* library's current version number */
	#    uint32_t compatibility_version;     /* library's compatibility vers number*/
	#};
	#union lc_str {
	#        uint32_t        offset; /* offset to the string */
	##ifndef __LP64__
	#        char            *ptr;   /* pointer to the string */
	##endif
	#};

	sysseek(FILE, $position, 0);
	sysread(FILE, $buffer, 12);
	
	if ($target eq "x86" || $target eq "x86_64" || $target eq "arm") { $unpackstring = "LLL" } else { $unpackstring = "NNN" };
	($cmd, $cmdsize, $offset) = unpack($unpackstring, $buffer);
	
	$sizetoread = $cmdsize - 12 - 12;
	$buffer = "";
	sysseek(FILE, $position+12, 0);
	# read string plus the other fields of dylib struct
	sysread(FILE, $buffer, $sizetoread+12);

	# name is last since it is stored that way in the file
	if ($target eq "x86" || $target eq "x86_64" || $target eq "arm") { $unpackstring = "LLLZ$sizetoread" } else { $unpackstring = "NNNZ$sizetoread" };
	($timestamp, $current_version, $compatibility_version, $name) = unpack($unpackstring, $buffer);
	
	printf("${bold}library path name:${normal} %s  [offset: 0x%08x]\n", $name, $position+24 );
	printf("${bold}timestamp:${normal} %s  [offset: 0x%08x]\n", ctime($timestamp), $position+=12 );
	printf("${bold}current version number:${normal} %d.%d.%d  [offset: 0x%08x]\n", $current_version >> 16, ($current_version >> 8) & 0xff, $current_version & 0xff, $position+=4 );
	printf("${bold}compatibility version:${normal} %d.%d.%d  [offset: 0x%08x]\n", $compatibility_version >> 16, ($compatibility_version >> 8) & 0xff, $compatibility_version & 0xff, $position+=4 );
}

### LC_CODE_SIGNATURE or LC_SEGMENT_SPLIT_INFO
sub process_linkedit_data_command
{
	my $buffer="";
	my $dataoff, $datasize;
	my ($position, $target, $targetbaseaddress, $loadcommandnumber) = @_;
	#struct linkedit_data_command {
	#    uint32_t    cmd;            /* LC_CODE_SIGNATURE or LC_SEGMENT_SPLIT_INFO */
	#    uint32_t    cmdsize;        /* sizeof(struct linkedit_data_command) */
	#    uint32_t    dataoff;        /* file offset of data in __LINKEDIT segment */
	#    uint32_t    datasize;       /* file size of data in __LINKEDIT segment  */
	#};
	# Total Size: 8 + 8 = 16 bytes

	sysseek(FILE, $position+8, 0);
	sysread(FILE, $buffer, 8);
	
	if ($target eq "x86" || $target eq "x86_64" || $target eq "arm") { $unpackstring = "LL" } else { $unpackstring = "NN" };	
	($dataoff, $datasize) = unpack($unpackstring, $buffer);

	printf("${bold}file offset:${normal} 0x%08x ${bold}real offset:${normal} 0x%08x  [offset: 0x%08x]\n", $dataoff, $targetbaseaddress+$dataoff, $position+=8);
	printf("${bold}size:${normal} %d bytes (0x%08x)  [offset: 0x%08x]\n", $datasize, $datasize, $position+=4);
}

### LC_UUID
sub process_uuid_command
{
	my $i;
	my $buffer="";
	my $dataoff, $datasize;
	my ($position, $target, $targetbaseaddress, $loadcommandnumber) = @_;
	#struct uuid_command {
	#    uint32_t    cmd;            /* LC_UUID */
	#    uint32_t    cmdsize;        /* sizeof(struct uuid_command) */
	#    uint8_t     uuid[16];       /* the 128-bit uuid */
	#};
	# Total Size: 8 + 4*4 = 12 bytes
	
	sysseek(FILE, $position+8, 0);
	sysread(FILE, $buffer, 16);
	
	if ($target eq "x86" || $target eq "x86_64" || $target eq "arm") { $unpackstring = "CCCCCCCCCCCCCCCC" } else { $unpackstring = "CCCCCCCCCCCCCCCC" };	
	@uuid = unpack($unpackstring, $buffer);

	print "${bold}uuid:${normal} ";
	for ($i=0; $i < 8 ; $i++)
	{
		printf("0x%02x ", $uuid[$i]);
	}
	print "\n      ";
	for ($i=8; $i < 16 ; $i++)
	{
		printf("0x%02x ", $uuid[$i]);
	}
	printf("  [offset: 0x%08x]\n", $position+8);
# FIXME: print the UUID as it appears in otool -l	
}

# TODO: Otool processes float, exception and debug states... Maybe not required ?
# read the flavor to see what is required
### LC_THREAD or  LC_UNIXTHREAD
sub process_thread_command
{
	my $buffer="";
	my $flavor, $count, $eax, $ebx, $ecx, $edx, $edi, $esi, $ebp, $esp, $ss, $eflags, $eip, $cs, $ds, $es, $fs, $gs;
	my $rax, $rbx, $rcx, $rdx, $rdi, $rsi, $rbp, $rsp, $r8, $r9, $r10, $r11, $r12, $r13, $r14, $r15, $rip, $rflags, $cs, $fs, $gs;
	my $flavor, $count, $srr0, $srr1, $r0, $r1, $r2, $r3, $r4, $r5, $r6, $r7, $r8, $r9, $r10, $r11, $r12, $r13, $r14, $r15, $r16, $r17, $r18, $r19, $r20, $r21, $r22, $r23,
		 $r24, $r25, $r26, $r27, $r28, $r29, $r30, $r31, $cr, $xer, $rlr, $ctr, $mq, $vrsave;
	
	my ($position, $target, $targetbaseaddress, $loadcommandnumber) = @_;
	
	my %threadstatedesc = ( 1=>"x86_THREAD_STATE32", 2=>"x86_FLOAT_STATE32", 3=>"x86_EXCEPTION_STATE32", 4=>"x86_THREAD_STATE64", 5=>"x86_FLOAT_STATE64",
							6=>"x86_EXCEPTION_STATE64", 7=>"x86_THREAD_STATE", 8=>"x86_FLOAT_STATE", 9=>"x86_EXCEPTION_STATE", 10=>"x86_DEBUG_STATE32",
							11=>"x86_DEBUG_STATE64", 12=>"x86_DEBUG_STATE", 13=>"THREAD_STATE_NONE");
							
	my %armthreadstatedesc = ( 1=>"ARM_THREAD_STATE", 2=>"ARM_VFP_STATE", 3=>"ARM_EXCEPTION_STATE", 4=>"ARM_DEBUG_STATE", 5=>"THREAD_STATE_NONE");

	my %ppcthreadstatedesc = ( 1=>"PPC_THREAD_STATE", 2=>"PPC_FLOAT_STATE", 3=>"PPC_EXCEPTION_STATE", 4=>"PPC_VECTOR_STATE", 5=>"PPC_THREAD_STATE64", 6=>"PPC_EXCEPTION_STATE64", 7=>"THREAD_STATE_NONE");
	#struct thread_command {
	#        uint32_t        cmd;            /* LC_THREAD or  LC_UNIXTHREAD */
	#        uint32_t        cmdsize;        /* total size of this command */
	#        /* uint32_t flavor                 flavor of thread state */
	#        /* uint32_t count                  count of longs in thread state */
	#        /* struct XXX_thread_state state   thread state for this flavor */
	#        /* ... */
	#};
	# Thread state is different for each cpu type
	
	# x86 @ /usr/include/mach/i386/_structs.h
	#_STRUCT_X86_THREAD_STATE32
	#{
	#    unsigned int        eax;
	#    unsigned int        ebx;
	#    unsigned int        ecx;
	#    unsigned int        edx;
	#    unsigned int        edi;
	#    unsigned int        esi;
	#    unsigned int        ebp;
	#    unsigned int        esp;
	#    unsigned int        ss;
	#    unsigned int        eflags;
	#    unsigned int        eip;
	#    unsigned int        cs;
	#    unsigned int        ds;
	#    unsigned int        es;
	#    unsigned int        fs;
	#    unsigned int        gs;
	#};
	# Total size: 8 + 8 + 16*4 = 80 bytes
	if ($target eq "x86")
	{
		sysseek(FILE, $position+8, 0);
		sysread(FILE, $buffer, 72);
		
		($flavor, $count, $eax, $ebx, $ecx, $edx, $edi, $esi, $ebp, $esp, $ss, $eflags, $eip, $cs, $ds, $es, $fs, $gs) = unpack("LLLLLLLLLLLLLLLLLL", $buffer);
		
		printf("${bold}flavor:${normal} %s  [offset: 0x%08x]\n", $threadstatedesc{$flavor}, $position+8);
#		printf("count: %s  [offset: 0x%08x]\n", $countstatedesc{$count}, $position+=4);
		printf("${bold}registers:${normal}\n");
	    printf("\teax 0x%08x ebx    0x%08x ecx 0x%08x edx 0x%08x\n", $eax, $ebx, $ecx, $edx);
		printf("\tedi 0x%08x esi    0x%08x ebp 0x%08x esp 0x%08x\n", $edi, $esi, $ebp, $esp);
		printf("\tss  0x%08x eflags 0x%08x eip 0x%08x cs  0x%08x\n", $ss, $eflags, $eip, $cs);
		printf("\tds  0x%08x es     0x%08x fs  0x%08x gs  0x%08x\n", $ds, $es, $fs, $gs);
		printf("${bold}Entry point (eip) offset:${normal} 0x%08x\n", $position+16+10*4);
	}

	# x86_64
	#_STRUCT_X86_THREAD_STATE64
	#{
	#        __uint64_t      rax;
	#        __uint64_t      rbx;
	#        __uint64_t      rcx;
	#        __uint64_t      rdx;
	#        __uint64_t      rdi;
	#        __uint64_t      rsi;
	#        __uint64_t      rbp;
	#        __uint64_t      rsp;
	#        __uint64_t      r8;
	#        __uint64_t      r9;
	#        __uint64_t      r10;
	#        __uint64_t      r11;
	#        __uint64_t      r12;
	#        __uint64_t      r13;
	#        __uint64_t      r14;
	#        __uint64_t      r15;
	#        __uint64_t      rip;
	#        __uint64_t      rflags;
	#        __uint64_t      cs;
	#        __uint64_t      fs;
	#        __uint64_t      gs;
	#};
	# Total size: 8 + 8 + 21 * 8 = 184 bytes
	if ($target eq "x86_64")
	{
		sysseek(FILE, $position+8, 0);
		sysread(FILE, $buffer, 176);
	
		($flavor, $count, $rax, $rbx, $rcx, $rdx, $rdi, $rsi, $rbp, $rsp, $r8, $r9, $r10, $r11, $r12, $r13, $r14, $r15, $rip, $rflags, $cs, $fs, $gs) = unpack("LLQQQQQQQQQQQQQQQQQQQQQ", $buffer);
		
		printf("${bold}flavor:${normal} %s  [offset: 0x%08x]\n", $threadstatedesc{$flavor}, $position+8);
		printf("${bold}registers:${normal}\n");
	    printf("   rax  0x%016llx rbx 0x%016llx rcx  0x%016llx\n", $rax, $rbx, $rcx);
		printf("   rdx  0x%016llx rdi 0x%016llx rsi  0x%016llx\n", $rdx, $rdi, $rsi);
		printf("   rbp  0x%016llx rsp 0x%016llx r8   0x%016llx\n", $rbp, $rsp, $r8);
		printf("    r9  0x%016llx r10 0x%016llx r11  0x%016llx\n", $r9, $r10, $r11);
		printf("   r12  0x%016llx r13 0x%016llx r14  0x%016llx\n", $r12, $r13, $r14);
		printf("   r15  0x%016llx rip 0x%016llx\n", $r15, $rip);
		printf("rflags  0x%016llx cs  0x%016llx fs   0x%016llx\n", $rflags, $cs, $fs);
		printf("    gs  0x%016llx\n", $gs);
		printf("${bold}Entry point (rip) offset:${normal} 0x%08x (don't forget that rip is 64 bits long)\n", $position+16+16*8);

	}

	# arm @ include/mach/arm/_structs.h
    #_STRUCT_ARM_THREAD_STATE
    #{
    #        __uint32_t      r[13];  /* General purpose register r0-r12 */
    #        __uint32_t      sp;             /* Stack pointer r13 */
    #        __uint32_t      lr;             /* Link register r14 */
    #        __uint32_t      pc;             /* Program counter r15 */
    #        __uint32_t      cpsr;           /* Current program status register */
    #};
	# Total size: 8 + 8 + 17*4 = 84 bytes
	if ($target =~ /arm/)
	{
		sysseek(FILE, $position+8, 0);
		sysread(FILE, $buffer, 76);
		
		($flavor, $count, $r0, $r1, $r2, $r3, $r4, $r5, $r6, $r7, $r8, $r9, $r10, $r11, $r12, $r13, $r14, $r15, $r16) = unpack("LLLLLLLLLLLLLLLLLLL", $buffer);
		
		printf("${bold}flavor:${normal} %s  [offset: 0x%08x]\n", $armthreadstatedesc{$flavor}, $position+8);
#		printf("count: %s  [offset: 0x%08x]\n", $countstatedesc{$count}, $position+=4);
		printf("${bold}registers:${normal}\n");
	    printf("\tr0   0x%08x r1   0x%08x r2   0x%08x r3   0x%08x\n", $r0, $r1, $r2, $r3);
		printf("\tr4   0x%08x r5   0x%08x r6   0x%08x r7   0x%08x\n", $r4, $r5, $r6, $r7);
		printf("\tr8   0x%08x r9   0x%08x r10  0x%08x r11  0x%08x\n", $r8, $r9, $r10, $r11);
		printf("\tr12  0x%08x r13  0x%08x r14  0x%08x r15  0x%08x\n", $r12, $r13, $r14, $r15);
		printf("\tr16  0x%08x\n", $r16);
#		printf("${bold}Entry point (eip) offset:${normal} 0x%08x\n", $position+16+10*4);
	}


	
	# ppc
	#_STRUCT_PPC_THREAD_STATE
	#{
	#        unsigned int srr0;      /* Instruction address register (PC) */
	#        unsigned int srr1;      /* Machine state register (supervisor) */
	#        unsigned int r0;
	#        unsigned int r1;
	#        unsigned int r2;
	#        unsigned int r3;
	#        unsigned int r4;
	#        unsigned int r5;
	#        unsigned int r6;
	#        unsigned int r7;
	#        unsigned int r8;
	#        unsigned int r9;
	#        unsigned int r10;
	#        unsigned int r11;
	#        unsigned int r12;
	#        unsigned int r13;
	#        unsigned int r14;
	#        unsigned int r15;
	#        unsigned int r16;
	#        unsigned int r17;
	#        unsigned int r18;
	#        unsigned int r19;
	#        unsigned int r20;
	#        unsigned int r21;
	#        unsigned int r22;
	#        unsigned int r23;
	#        unsigned int r24;
	#        unsigned int r25;
	#        unsigned int r26;
	#        unsigned int r27;
	#        unsigned int r28;
	#        unsigned int r29;
	#        unsigned int r30;
	#        unsigned int r31;
	#        unsigned int cr;        /* Condition register */
	#        unsigned int xer;       /* User's integer exception register */
	#        unsigned int lr;        /* Link register */
	#        unsigned int ctr;       /* Count register */
	#        unsigned int mq;        /* MQ register (601 only) */
	#        unsigned int vrsave;    /* Vector Save Register */
	#};
	# Total Size: 8 + 8 + 40 * 4 = 176 bytes
	if ($target eq "ppc")
	{
		sysseek(FILE, $position+8, 0);
		sysread(FILE, $buffer, 168);

		($flavor, $count, $srr0, $srr1, $r0, $r1, $r2, $r3, $r4, $r5, $r6, $r7, $r8, $r9, $r10, $r11, $r12, $r13, $r14, $r15, $r16, $r17, $r18, $r19, $r20, $r21, $r22, $r23,
		 $r24, $r25, $r26, $r27, $r28, $r29, $r30, $r31, $cr, $xer, $rlr, $ctr, $mq, $vrsave) = unpack("NNNNNNNNNNNNNNNNNNNNNNNNNNNNNNNNNNNNNNNN", $buffer);
		 
		printf("${bold}flavor:${normal} %s  [offset: 0x%08x]\n", $ppcthreadstatedesc{$flavor}, $position+8);
		printf("${bold}registers:${normal}\n");
	    printf("    r0  0x%08x r1  0x%08x r2  0x%08x r3   0x%08x r4   0x%08x\n", $r0 ,$r1 ,$r2 ,$r3 ,$r4);
		printf("    r5  0x%08x r6  0x%08x r7  0x%08x r8   0x%08x r9   0x%08x\n", $r5 ,$r6 ,$r7 ,$r8 ,$r9);
		printf("    r10 0x%08x r11 0x%08x r12 0x%08x r13  0x%08x r14  0x%08x\n", $r10 ,$r11 ,$r12 ,$r13 ,$r14);
		printf("    r15 0x%08x r16 0x%08x r17 0x%08x r18  0x%08x r19  0x%08x\n", $r15 ,$r16 ,$r17 ,$r18 ,$r19);
		printf("    r20 0x%08x r21 0x%08x r22 0x%08x r23  0x%08x r24  0x%08x\n", $r20 ,$r21 ,$r22 ,$r23 ,$r24);
		printf("    r25 0x%08x r26 0x%08x r27 0x%08x r28  0x%08x r29  0x%08x\n", $r25 ,$r26 ,$r27 ,$r28 ,$r29);
		printf("    r30 0x%08x r31 0x%08x cr  0x%08x xer  0x%08x lr   0x%08x\n", $r30 ,$r31, $cr, $xer, $lr);
		printf("    ctr 0x%08x mq  0x%08x vrsave 0x%08x srr0 0x%08x srr1 0x%08x\n", $ctr, $mq, $vrsave, $srr0, $srr1);
		printf("${bold}Entry point (srr0) offset:${normal} 0x%08x\n", $position+16);
	}
}

### LC_SYMSEG
sub process_symseg_command
{
	my $buffer="";
	my $offset, $size;
	my ($position, $target, $targetbaseaddress, $loadcommandnumber) = @_;
	#struct symseg_command {
	#        uint32_t        cmd;            /* LC_SYMSEG */
	#        uint32_t        cmdsize;        /* sizeof(struct symseg_command) */
	#        uint32_t        offset;         /* symbol segment offset */
	#        uint32_t        size;           /* symbol segment size in bytes */
	#};
	# Total Size: 8 + 8 = 16 bytes

	sysseek(FILE, $position+8, 0);
	sysread(FILE, $buffer, 8);
	
	if ($target eq "x86" || $target eq "x86_64" || $target eq "arm") { $unpackstring = "LL" } else { $unpackstring = "NN" };	
	($offset, $size) = unpack($unpackstring, $buffer);
	
	printf("${bold}symbol segment offset:${normal} 0x%08x ${bold}real offset:${normal} 0x%08x  [offset: 0x%08x]\n", $offset, $targetbaseaddress+$offset, $position+=8);
	printf("${bold}size:${normal} %d bytes (0x%08x)  [offset: 0x%08x]\n", $size, $size, $position+=4);
}

### LC_ROUTINES or LC_ROUTINES_64
sub process_routines_command
{
	my $buffer="";
	my $init_address, $init_module, $reserved1, $reserved2, $reserved3, $reserved4, $reserved5, $reserved6;
	my ($position, $target, $targetbaseaddress, $loadcommandnumber) = @_;
	# 32 bits
	#struct routines_command { /* for 32-bit architectures */
	#        uint32_t        cmd;            /* LC_ROUTINES */
	#        uint32_t        cmdsize;        /* total size of this command */
	#        uint32_t        init_address;   /* address of initialization routine */
	#        uint32_t        init_module;    /* index into the module table that */
	#                                        /*  the init routine is defined in */
	#        uint32_t        reserved1;
	#        uint32_t        reserved2;
	#        uint32_t        reserved3;
	#        uint32_t        reserved4;
	#        uint32_t        reserved5;
	#        uint32_t        reserved6;
	#};
	# Total Size: 8 + 8*4 = 40 bytes
	
	# 64 bits
	#struct routines_command_64 { /* for 64-bit architectures */
	#        uint32_t        cmd;            /* LC_ROUTINES_64 */
	#        uint32_t        cmdsize;        /* total size of this command */
	#        uint64_t        init_address;   /* address of initialization routine */
	#        uint64_t        init_module;    /* index into the module table that */
	#                                        /*  the init routine is defined in */
	#        uint64_t        reserved1;
	#        uint64_t        reserved2;
	#        uint64_t        reserved3;
	#        uint64_t        reserved4;
	#        uint64_t        reserved5;
	#        uint64_t        reserved6;
	#};
	# Total size: 8 + 8 * 8 = 72 bytes

	sysseek(FILE, $position+8, 0);
	sysread(FILE, $buffer, 40) if ($target eq "x86" || $target eq "ppc" || $target eq "arm");
	sysread(FILE, $buffer, 72) if ($target eq "x86_64");
	
	if ($target eq "x86" || $target eq "arm") { $unpackstring = "LLLLLLLL" }
	elsif ($target eq "x86_64") { $unpackstring ="QQQQQQQQ"}
	else { $unpackstring = "NNNNNNNN" };	
	
	($init_address, $init_module, $reserved1, $reserved2, $reserved3, $reserved4, $reserved5, $reserved6) = unpack($unpackstring, $buffer);
	
	if ($target eq "x86" || $target eq "ppc" || $target eq "arm")
	{
		printf("${bold}initialization routine address:${normal} 0x%08x  [offset: 0x%08x]\n", $init_address, $position+=8);
		printf("${bold}module table index:${normal} %d (0x%08x)  [offset: 0x%08x]\n", $init_module, $init_module, $position+=4);
		printf("${bold}reserved1:${normal} 0x%08x  [offset: 0x%08x]\n", $reserved1, $position+=4);
		printf("${bold}reserved2:${normal} 0x%08x  [offset: 0x%08x]\n", $reserved2, $position+=4);
		printf("${bold}reserved3:${normal} 0x%08x  [offset: 0x%08x]\n", $reserved3, $position+=4);
		printf("${bold}reserved4:${normal} 0x%08x  [offset: 0x%08x]\n", $reserved4, $position+=4);
		printf("${bold}reserved5:${normal} 0x%08x  [offset: 0x%08x]\n", $reserved5, $position+=4);
		printf("${bold}reserved6:${normal} 0x%08x  [offset: 0x%08x]\n", $reserved6, $position+=4);
	}
	else 
	{
		printf("${bold}initialization routine address:${normal} 0x%016llx  [offset: 0x%08x]\n", $init_address, $position+=8);
		printf("${bold}module table index:${normal} %d (0x%016llx)  [offset: 0x%08x]\n", $init_module, $init_module, $position+=8);
		printf("${bold}reserved1:${normal} 0x%08x  [offset: 0x%016llx]\n", $reserved1, $position+=8);
		printf("${bold}reserved2:${normal} 0x%08x  [offset: 0x%016llx]\n", $reserved2, $position+=8);
		printf("${bold}reserved3:${normal} 0x%08x  [offset: 0x%016llx]\n", $reserved3, $position+=8);
		printf("${bold}reserved4:${normal} 0x%08x  [offset: 0x%016llx]\n", $reserved4, $position+=8);
		printf("${bold}reserved5:${normal} 0x%08x  [offset: 0x%016llx]\n", $reserved5, $position+=8);
		printf("${bold}reserved6:${normal} 0x%08x  [offset: 0x%016llx]\n", $reserved6, $position+=8);	
	}
}

# TODO: all these that have the same kind of structure could be packed into a single generic routine.
### LC_SUB_FRAMEWORK
sub process_sub_framework_command
{
	my $buffer="";
	my $cmd, $cmdsize, $offset, $name;
	my ($position, $target, $targetbaseaddress, $loadcommandnumber) = @_;
	#struct sub_framework_command {
	#        uint32_t        cmd;            /* LC_SUB_FRAMEWORK */
	#        uint32_t        cmdsize;        /* includes umbrella string */
	#        union lc_str    umbrella;       /* the umbrella framework name */
	#};
	# Total Size: 8 + variable size string = 
	
	sysseek(FILE, $position, 0);
	sysread(FILE, $buffer, 12);
	
	if ($target eq "x86" || $target eq "x86_64" || $target eq "arm") { $unpackstring = "LLL" } else { $unpackstring = "NNN" };
	($cmd, $cmdsize, $offset) = unpack($unpackstring, $buffer);
	
	$sizetoread = $cmdsize - 12;
	
	sysseek(FILE, $position+12, 0);
	sysread(FILE, $buffer, $sizetoread);
	
	($name) = unpack("Z$sizetoread", $buffer);
	
	printf("${bold}umbrella framework name:${normal} %s  [offset: 0x%08x]\n", $name, $position+12 );
}


### LC_SUB_UMBRELLA
sub process_sub_umbrella_command
{
	my $buffer="";
	my $cmd, $cmdsize, $offset, $name;
	my ($position, $target, $targetbaseaddress, $loadcommandnumber) = @_;
	#struct sub_umbrella_command {
	#        uint32_t        cmd;            /* LC_SUB_UMBRELLA */
	#        uint32_t        cmdsize;        /* includes sub_umbrella string */
	#        union lc_str    sub_umbrella;   /* the sub_umbrella framework name */
	#};
	# Total Size: 8 + variable size string = 
	
	sysseek(FILE, $position, 0);
	sysread(FILE, $buffer, 12);
	
	if ($target eq "x86" || $target eq "x86_64" || $target eq "arm") { $unpackstring = "LLL" } else { $unpackstring = "NNN" };
	($cmd, $cmdsize, $offset) = unpack($unpackstring, $buffer);
	
	$sizetoread = $cmdsize - 12;
	
	sysseek(FILE, $position+12, 0);
	sysread(FILE, $buffer, $sizetoread);
	
	($name) = unpack("Z$sizetoread", $buffer);
	
	printf("${bold}sub_umbrella framework name:${normal} %s  [offset: 0x%08x]\n", $name, $position+12 );
}

### LC_SUB_CLIENT
sub process_sub_client_command
{
	my $buffer="";
	my $cmd, $cmdsize, $offset, $name;
	my ($position, $target, $targetbaseaddress, $loadcommandnumber) = @_;
	#struct sub_client_command {
	#        uint32_t        cmd;            /* LC_SUB_CLIENT */
	#        uint32_t        cmdsize;        /* includes client string */
	#        union lc_str    client;         /* the client name */
	#};
	# Total Size: 8 + variable size string = 
	
	sysseek(FILE, $position, 0);
	sysread(FILE, $buffer, 12);
	
	if ($target eq "x86" || $target eq "x86_64" || $target eq "arm") { $unpackstring = "LLL" } else { $unpackstring = "NNN" };
	($cmd, $cmdsize, $offset) = unpack($unpackstring, $buffer);
	
	$sizetoread = $cmdsize - 12;
	
	sysseek(FILE, $position+12, 0);
	sysread(FILE, $buffer, $sizetoread);
	
	($name) = unpack("Z$sizetoread", $buffer);
	
	printf("${bold}client name:${normal} %s  [offset: 0x%08x]\n", $name, $position+12 );
}

### LC_SUB_LIBRARY
sub process_sub_library_command
{
	my $buffer="";
	my $cmd, $cmdsize, $offset, $name;
	my ($position, $target, $targetbaseaddress, $loadcommandnumber) = @_;
	#struct sub_library_command {
	#        uint32_t        cmd;            /* LC_SUB_LIBRARY */
	#        uint32_t        cmdsize;        /* includes sub_library string */
	#        union lc_str    sub_library;    /* the sub_library name */
	#};
	# Total Size: 8 + variable size string = 
	
	sysseek(FILE, $position, 0);
	sysread(FILE, $buffer, 12);
	
	if ($target eq "x86" || $target eq "x86_64" || $target eq "arm") { $unpackstring = "LLL" } else { $unpackstring = "NNN" };
	($cmd, $cmdsize, $offset) = unpack($unpackstring, $buffer);
	
	$sizetoread = $cmdsize - 12;
	
	sysseek(FILE, $position+12, 0);
	sysread(FILE, $buffer, $sizetoread);
	
	($name) = unpack("Z$sizetoread", $buffer);
	
	printf("${bold}sub_library name:${normal} %s  [offset: 0x%08x]\n", $name, $position+12 );
}

### LC_TWOLEVEL_HINTS
sub process_twolevel_hints_command
{
	my $buffer="";
	my $offset, $nhints;
	my ($position, $target, $targetbaseaddress, $loadcommandnumber) = @_;
	#struct twolevel_hints_command {
	#    uint32_t cmd;       /* LC_TWOLEVEL_HINTS */
	#    uint32_t cmdsize;   /* sizeof(struct twolevel_hints_command) */
	#    uint32_t offset;    /* offset to the hint table */
	#    uint32_t nhints;    /* number of hints in the hint table */
	#};
	# Total size: 8 + 8 = 16 bytes

	sysseek(FILE, $position+8, 0);
	sysread(FILE, $buffer, 8);
	
	if ($target eq "x86" || $target eq "x86_64" || $target eq "arm") { $unpackstring = "LL" } else { $unpackstring = "NN" };	
	($offset, $nhints) = unpack($unpackstring, $buffer);

	printf("${bold}offset to hint table:${normal} 0x%08x ${bold}real offset:${normal} 0x%08x  [offset: 0x%08x]\n", $offset, $targetbaseaddress+$offset, $position+=8);
	printf("${bold}number of hints:${normal} %d (0x%08x)  [offset: 0x%08x]\n", $nhints, $nhints, $position+=4);
}

### LC_PREBIND_CKSUM
sub process_prebind_cksum_command
{
	my $buffer="";
	my $cksum;
	my ($position, $target, $targetbaseaddress, $loadcommandnumber) = @_;
	#struct prebind_cksum_command {
	#    uint32_t cmd;       /* LC_PREBIND_CKSUM */
	#    uint32_t cmdsize;   /* sizeof(struct prebind_cksum_command) */
	#    uint32_t cksum;     /* the check sum or zero */
	#};
	# Total size: 8 + 4 bytes = 12 bytes

	sysseek(FILE, $position+8, 0);
	sysread(FILE, $buffer, 4);
	
	if ($target eq "x86" || $target eq "x86_64" || $target eq "arm") { $unpackstring = "L" } else { $unpackstring = "N" };	
	($cksum) = unpack($unpackstring, $buffer);

	printf("${bold}check sum:${normal} 0x%08x  [offset: 0x%08x]\n", $cksum, $position+=8);
}

### LC_ENCRYPTION_INFO
sub process_encryption_info_command
{
	my $buffer="";
	my $cryptoff, $cryptsize, $cryptid;
	my ($position, $target, $targetbaseaddress, $loadcommandnumber) = @_;
	#struct encryption_info_command {
	#   uint32_t     cmd;            /* LC_ENCRYPTION_INFO */
	#   uint32_t     cmdsize;        /* sizeof(struct encryption_info_command) */
	#   uint32_t     cryptoff;       /* file offset of encrypted range */
	#   uint32_t     cryptsize;      /* file size of encrypted range */
	#   uint32_t     cryptid;        /* which enryption system,
	#                                   0 means not-encrypted yet */
	#};
	# Total size: 8 + 3*4 = 20 bytes

	sysseek(FILE, $position+8, 0);
	sysread(FILE, $buffer, 12);
	
	if ($target eq "x86" || $target eq "x86_64" || $target eq "arm") { $unpackstring = "LLL" } else { $unpackstring = "NNN" };	
	($cryptoff, $cryptsize, $cryptid) = unpack($unpackstring, $buffer);
	
	printf("${bold}encrypted range offset:${normal} 0x%08x ${bold}real offset:${normal} 0x%08x  [offset: 0x%08x]\n", $cryptoff, $targetbaseaddress+$cryptoff, $position+=8);
	printf("${bold}size:${normal} %d bytes (0x%08x)  [offset: 0x%08x]\n", $cryptsize, $cryptsize, $position+=4);
	if ($cryptid == 0)
	{
		printf("${bold}encryption system:${normal} not encrypted yet  [offset: 0x%08x]\n", $position+=4);
	}
	else
	{
		printf("${bold}encryption system:${normal} %d  [offset: 0x%08x]\n", $cryptid, $position+=4);
	}
}

### LC_RPATH
sub process_rpath_command
{
	my $buffer="";
	my $cmd, $cmdsize, $offset, $path;
	my ($position, $target, $targetbaseaddress, $loadcommandnumber) = @_;
	#struct rpath_command {
	#    uint32_t     cmd;           /* LC_RPATH */
	#    uint32_t     cmdsize;       /* includes string */
	#    union lc_str path;          /* path to add to run path */
	#};
	# Total Size: 8 + variable size string = 
	
	sysseek(FILE, $position, 0);
	sysread(FILE, $buffer, 12);
	
	if ($target eq "x86" || $target eq "x86_64" || $target eq "arm") { $unpackstring = "LLL" } else { $unpackstring = "NNN" };
	($cmd, $cmdsize, $offset) = unpack($unpackstring, $buffer);
	
	$sizetoread = $cmdsize - 12;
	
	sysseek(FILE, $position+12, 0);
	sysread(FILE, $buffer, $sizetoread);
	
	($path) = unpack("Z$sizetoread", $buffer);
	
	printf("${bold}path to add ro run path:${normal} %s  [offset: 0x%08x]\n", $path, $position+12 );
}




### process and modify entrypoint (code based on process_thread_command routine)
sub modify_eip
{
	my $buffer="";
	my $flavor, $count, $eax, $ebx, $ecx, $edx, $edi, $esi, $ebp, $esp, $ss, $eflags, $eip, $cs, $ds, $es, $fs, $gs;
	my $rax, $rbx, $rcx, $rdx, $rdi, $rsi, $rbp, $rsp, $r8, $r9, $r10, $r11, $r12, $r13, $r14, $r15, $rip, $rflags, $cs, $fs, $gs;
	my $flavor, $count, $srr0, $srr1, $r0, $r1, $r2, $r3, $r4, $r5, $r6, $r7, $r8, $r9, $r10, $r11, $r12, $r13, $r14, $r15, $r16, $r17, $r18, $r19, $r20, $r21, $r22, $r23,
		 $r24, $r25, $r26, $r27, $r28, $r29, $r30, $r31, $cr, $xer, $rlr, $ctr, $mq, $vrsave;
	my $newentrypoint;
	
	my ($position, $target, $targetbaseaddress, $loadcommandnumber) = @_;
	
	#struct thread_command {
	#        uint32_t        cmd;            /* LC_THREAD or  LC_UNIXTHREAD */
	#        uint32_t        cmdsize;        /* total size of this command */
	#        /* uint32_t flavor                 flavor of thread state */
	#        /* uint32_t count                  count of longs in thread state */
	#        /* struct XXX_thread_state state   thread state for this flavor */
	#        /* ... */
	#};
	# Thread state is different for each cpu type
	
	# x86 @ /usr/include/mach/i386/_structs.h
	#_STRUCT_X86_THREAD_STATE32
	#{
	#    unsigned int        eax;
	#    unsigned int        ebx;
	#    unsigned int        ecx;
	#    unsigned int        edx;
	#    unsigned int        edi;
	#    unsigned int        esi;
	#    unsigned int        ebp;
	#    unsigned int        esp;
	#    unsigned int        ss;
	#    unsigned int        eflags;
	#    unsigned int        eip;
	#    unsigned int        cs;
	#    unsigned int        ds;
	#    unsigned int        es;
	#    unsigned int        fs;
	#    unsigned int        gs;
	#};
	# Total size: 8 + 8 + 16*4 = 80 bytes
	if ($target eq "x86")
	{
		sysseek(FILE, $position+16+10*4, 0);
		sysread(FILE, $buffer, 4);
		
		($eip) = unpack("L", $buffer);
		
		#printf("${bold}flavor:${normal} %s  [offset: 0x%08x]\n", $threadstatedesc{$flavor}, $position+8);
		printf("${bold}Current entrypoint is:${normal} 0x%08x\n", $eip);
		printf("${bold}Entry point (eip) offset:${normal} 0x%08x\n", $position+16+10*4);
		printf("${bold}New entry point will be:${normal} 0x%08x\n", hex($arg{e}));
		($newentrypoint) = pack("V", hex($arg{e}));
		sysseek(FILE, $position+16+10*4, 0);
		# introduce checks, for example for permissions
		syswrite(FILE, $newentrypoint,4) or die("ERROR: Couldn't write entrypoint!");
	}

	# x86_64
	#_STRUCT_X86_THREAD_STATE64
	#{
	#        __uint64_t      rax;
	#        __uint64_t      rbx;
	#        __uint64_t      rcx;
	#        __uint64_t      rdx;
	#        __uint64_t      rdi;
	#        __uint64_t      rsi;
	#        __uint64_t      rbp;
	#        __uint64_t      rsp;
	#        __uint64_t      r8;
	#        __uint64_t      r9;
	#        __uint64_t      r10;
	#        __uint64_t      r11;
	#        __uint64_t      r12;
	#        __uint64_t      r13;
	#        __uint64_t      r14;
	#        __uint64_t      r15;
	#        __uint64_t      rip;
	#        __uint64_t      rflags;
	#        __uint64_t      cs;
	#        __uint64_t      fs;
	#        __uint64_t      gs;
	#};
	# Total size: 8 + 8 + 21 * 8 = 184 bytes
	if ($target eq "x86_64")
	{
		sysseek(FILE, $position+16+16*8, 0);
		sysread(FILE, $buffer, 8);
	
		($rip) = unpack("Q", $buffer);

		printf("${bold}Current entrypoint is:${normal} 0x%016x\n", $rip);
		printf("${bold}Entry point (rip) offset:${normal} 0x%08x (don't forget that rip is 64 bits long)\n", $position+16+16*8);
		printf("${bold}New entry point will be:${normal} 0x%016x\n", hex($arg{e}));
		# humm V is 32bit only!
		($newentrypoint) = pack("V", hex($arg{e}));
		sysseek(FILE, $position+16+16*8, 0);
		syswrite(FILE, $newentrypoint,8) or die("ERROR: Couldn't write entrypoint!");
	}
	
	# ppc
	#_STRUCT_PPC_THREAD_STATE
	#{
	#        unsigned int srr0;      /* Instruction address register (PC) */
	#        unsigned int srr1;      /* Machine state register (supervisor) */
	#        unsigned int r0;
	#        unsigned int r1;
	#        unsigned int r2;
	#        unsigned int r3;
	#        unsigned int r4;
	#        unsigned int r5;
	#        unsigned int r6;
	#        unsigned int r7;
	#        unsigned int r8;
	#        unsigned int r9;
	#        unsigned int r10;
	#        unsigned int r11;
	#        unsigned int r12;
	#        unsigned int r13;
	#        unsigned int r14;
	#        unsigned int r15;
	#        unsigned int r16;
	#        unsigned int r17;
	#        unsigned int r18;
	#        unsigned int r19;
	#        unsigned int r20;
	#        unsigned int r21;
	#        unsigned int r22;
	#        unsigned int r23;
	#        unsigned int r24;
	#        unsigned int r25;
	#        unsigned int r26;
	#        unsigned int r27;
	#        unsigned int r28;
	#        unsigned int r29;
	#        unsigned int r30;
	#        unsigned int r31;
	#        unsigned int cr;        /* Condition register */
	#        unsigned int xer;       /* User's integer exception register */
	#        unsigned int lr;        /* Link register */
	#        unsigned int ctr;       /* Count register */
	#        unsigned int mq;        /* MQ register (601 only) */
	#        unsigned int vrsave;    /* Vector Save Register */
	#};
	# Total Size: 8 + 8 + 40 * 4 = 176 bytes
	if ($target eq "ppc")
	{
		sysseek(FILE, $position+16, 0);
		sysread(FILE, $buffer, 4);

		($srr0) = unpack("N", $buffer);

		printf("${bold}Current entrypoint is:${normal} 0x%08x\n", $srr0);		 
		printf("${bold}Entry point (srr0) offset:${normal} 0x%08x\n", $position+16);
		printf("${bold}New entry point will be:${normal} 0x%08x\n", hex($arg{e}));
		# humm V is 32bit only!
		($newentrypoint) = pack("N", hex($arg{e}));
		sysseek(FILE, $position+16, 0);
		syswrite(FILE, $newentrypoint,4) or die("ERROR: Couldn't write entrypoint!");
	}

	# arm @ include/mach/arm/_structs.h
    #_STRUCT_ARM_THREAD_STATE
    #{
    #        __uint32_t      r[13];  /* General purpose register r0-r12 */
    #        __uint32_t      sp;             /* Stack pointer r13 */
    #        __uint32_t      lr;             /* Link register r14 */
    #        __uint32_t      pc;             /* Program counter r15 */
    #        __uint32_t      cpsr;           /* Current program status register */
    #};
	# Total size: 8 + 8 + 17*4 = 84 bytes
	if ($target =~ /arm/)
	{
		sysseek(FILE, $position+16+15*4, 0);
		sysread(FILE, $buffer, 4);
		
		($r15) = unpack("L", $buffer);

		printf("${bold}Current entrypoint is:${normal} 0x%08x\n", $r15);
		printf("${bold}Entry point (r15) offset:${normal} 0x%08x\n", $position+16+15*4);
		printf("${bold}New entry point will be:${normal} 0x%08x\n", hex($arg{e}));
		($newentrypoint) = pack("V", hex($arg{e}));
		sysseek(FILE, $position+16+15*4, 0);
		# introduce checks, for example for permissions
		syswrite(FILE, $newentrypoint,4) or die("ERROR: Couldn't write entrypoint!");
		printf("\nIf this is a iOS binary don't forget you need to update code signature!\n");
	}

}