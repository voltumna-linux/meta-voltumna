/*****************************************************************************
*
* Copyright (c) 2014, Advanced Micro Devices, Inc.   
* All rights reserved.   
*
* Redistribution and use in source and binary forms, with or without   
* modification, are permitted provided that the following conditions are met:   
*     * Redistributions of source code must retain the above copyright   
*       notice, this list of conditions and the following disclaimer.   
*     * Redistributions in binary form must reproduce the above copyright   
*       notice, this list of conditions and the following disclaimer in the   
*       documentation and/or other materials provided with the distribution.   
*     * Neither the name of Advanced Micro Devices, Inc. nor the names of    
*       its contributors may be used to endorse or promote products derived    
*       from this software without specific prior written permission.   
*    
* THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS" AND   
* ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED   
* WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE   
* DISCLAIMED. IN NO EVENT SHALL ADVANCED MICRO DEVICES, INC. BE LIABLE FOR ANY   
* DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES   
* (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES;   
* LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND   
* ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT   
* (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS   
* SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.   
*    
*   
***************************************************************************/
#include <stdio.h>
#include <stdlib.h>
#include <unistd.h>
#include <fcntl.h>
#include <signal.h>
#include <readline/readline.h>
#include <linux/watchdog.h>

#define WATCHDOG_APP_VERSION	"0.1"

int fd;		/* /dev/watchdog file descriptor */
volatile int ping;

char *show_prompt(void)
{
	return "$ ";
}

void sighandler(int sig)
{
	printf("\n%s", show_prompt());
}

void pinghandler(int sig)
{
	ping = 0;
	printf("\n");
	/* Set the signal handler back to the original */
	signal(SIGINT, sighandler);
}

void show_license(void)
{
	printf("/*****************************************************************************\n"
	       "*\n"
	       "* Copyright (c) 2014, Advanced Micro Devices, Inc.\n"
	       "* All rights reserved.\n"
	       "*\n"
	       "* Redistribution and use in source and binary forms, with or without\n" 
	       "* modification, are permitted provided that the following conditions are met:\n"
	       "*     * Redistributions of source code must retain the above copyright\n"
	       "*       notice, this list of conditions and the following disclaimer.\n"
	       "*     * Redistributions in binary form must reproduce the above copyright\n"
	       "*       notice, this list of conditions and the following disclaimer in the\n"
	       "*       documentation and/or other materials provided with the distribution.\n"
	       "*     * Neither the name of Advanced Micro Devices, Inc. nor the names of\n"
	       "*       its contributors may be used to endorse or promote products derived\n"
	       "*       from this software without specific prior written permission.\n"
	       "*\n"
	       "* THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS \"AS IS\" AND\n"
	       "* ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED\n"
	       "* WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE\n"
	       "* DISCLAIMED. IN NO EVENT SHALL ADVANCED MICRO DEVICES, INC. BE LIABLE FOR ANY\n"
	       "* DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES\n"
	       "* (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES;\n"
	       "* LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND\n"
	       "* ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT\n"
	       "* (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS\n"
	       "* SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.\n"
	       "*\n"
	       "*\n"
	       "***************************************************************************/\n");
}

void print_usage()
{
	printf("\nCommands Supported ->\n");
	printf(" disablewatchdog       : Disables the Watchdog Timer\n");
	printf(" enablewatchdog        : Enables the Watchdog Timer\n");
	printf(" getfeatures           : Shows the features supported by the Watchdog implementation\n");
	printf(" getstatus             : Gives the current status of Watchdog Timer\n");
	printf(" getbootstatus         : Displays the status of Watchdog Hardware after reboot or fresh boot\n");
	printf(" ping                  : Resets Watchdog Timer at regular intervals\n");
	printf(" gettimeout            : Gives the value of Watchdog timeout (in frequency units)\n");
	printf(" gettimeleft           : Gives the current value of Watchdog Timer (in frequency units)\n");
	printf(" sendmagicchar         : Sends the magic character 'V' to the Watchdog device\n");
	printf(" settimeout <timeout>  : Sets the new value for Watchdog timeout (in frequency units)\n");
	printf(" license               : Displays the terms of LICENSE for this application\n");
	printf(" help                  : Displays help text\n");
	printf(" exit                  : Exits the application\n\n");
}

void parse_cmd(const char *cmdline)
{
	if ((cmdline == NULL) || (strncmp(cmdline, "exit", 4) == 0)) {
		printf("\nExiting...\n");
		printf("\nIf the Watchdog Timer was not disabled, and you did not send the magic character,\n"
			"Watchdog Timer is still ticking, and your system will reboot soon\n");

		if(close(fd) < 0)
			perror("Error closing /dev/watchdog");
		exit(EXIT_SUCCESS);
	} else if (strncmp(cmdline, "help", 4) == 0)
		print_usage();
	else if (strncmp(cmdline, "disablewatchdog", 7) == 0) {
		int flags;

		printf("\nDisabling watchdog timer...\n");
		flags = WDIOS_DISABLECARD;
		if (ioctl(fd, WDIOC_SETOPTIONS, &flags) < 0)
			perror("Could not disable watchdog");
	} else if (strncmp(cmdline, "enablewatchdog", 6) == 0) {
		int flags;

		printf("\nEnabling watchdog timer...\n");
		flags = WDIOS_ENABLECARD;
		if (ioctl(fd, WDIOC_SETOPTIONS, &flags) < 0)
			printf("Could not enable watchdog");
	} else if (strncmp(cmdline, "getfeatures", 10) == 0) {
		struct watchdog_info info;

		if(ioctl(fd, WDIOC_GETSUPPORT, &info) < 0)
			perror("Could not get watchdog features");

		printf("\nIdentity:\t\t%s\n", info.identity);
		printf("Firmware Version:\t%u\n", info.firmware_version);
		printf("Options Set: \n"
			"%s%s%s%s%s%s%s%s%s%s%s\n",
			info.options & WDIOF_OVERHEAT ? "\t\t\tReset due to CPU overheat\n": "",
			info.options & WDIOF_FANFAULT ? "\t\t\tFan failed\n": "",
			info.options & WDIOF_EXTERN1 ? "\t\t\tExternal relay 1\n": "",
			info.options & WDIOF_EXTERN2 ? "\t\t\tExternal relay 2\n": "",
			info.options & WDIOF_POWERUNDER ? "\t\t\tPower bad/power fault\n": "",
			info.options & WDIOF_CARDRESET ? "\t\t\tCard previously reset the CPU\n": "",
			info.options & WDIOF_POWEROVER ? "\t\t\tPower over voltage\n": "",
			info.options & WDIOF_SETTIMEOUT ? "\t\t\tSet timeout (in frequency units)\n": "",
			info.options & WDIOF_MAGICCLOSE ? "\t\t\tSupports magic close character\n": "",
			info.options & WDIOF_PRETIMEOUT ? "\t\t\tPretimeout (in frequency units)\n": "",
			info.options & WDIOF_KEEPALIVEPING ? "\t\t\tKeep alive ping reply\n": "");
	} else if (strncmp(cmdline, "getstatus", 9) == 0) {
		int status;

		printf("\n");
		if(ioctl(fd, WDIOC_GETSTATUS, &status) < 0)
			perror("Could not get watchdog status");

		if (status & (1 << 0))
			printf("\nWatchdog device is active\n");
		if (status & (1 << 1))
			printf("Watchdog device opened via /dev/watchdog\n");
		if (status & (1 << 2))
			printf("Received magic char\n");
		if (status & (1 << 3))
			printf("nowayout set\n");
		if (status & (1 << 4))
			printf("Watchdog device unregistered\n");
	} else if (strncmp(cmdline, "getbootstatus", 7) == 0) {
		int bootstatus;

		if(ioctl(fd, WDIOC_GETBOOTSTATUS, &bootstatus) < 0)
			perror("Could not get bootstatus");

		printf("\nbootstatus: \n"
			"%s%s%s%s%s%s%s%s%s%s%s\n",
			bootstatus & WDIOF_OVERHEAT ? "\t\t\tReset due to CPU overheat\n": "",
			bootstatus & WDIOF_FANFAULT ? "\t\t\tFan failed\n": "",
			bootstatus & WDIOF_EXTERN1 ? "\t\t\tExternal relay 1\n": "",
			bootstatus & WDIOF_EXTERN2 ? "\t\t\tExternal relay 2\n": "",
			bootstatus & WDIOF_POWERUNDER ? "\t\t\tPower bad/power fault\n": "",
			bootstatus & WDIOF_CARDRESET ? "\t\t\tCard previously reset the CPU\n": "",
			bootstatus & WDIOF_POWEROVER ? "\t\t\tPower over voltage\n": "",
			bootstatus & WDIOF_SETTIMEOUT ? "\t\t\tSet timeout (in frequency units)\n": "",
			bootstatus & WDIOF_MAGICCLOSE ? "\t\t\tSupports magic close character\n": "",
			bootstatus & WDIOF_PRETIMEOUT ? "\t\t\tPretimeout (in frequency units)\n": "",
			bootstatus & WDIOF_KEEPALIVEPING ? "\t\t\tKeep alive ping reply\n": "");
	} else if (strncmp(cmdline, "ping", 4) == 0) {
		int dummy;

		printf("\nContinuosly resetting Watchdog...press Ctrl+C to stop\n");
		printf("\nOnce you stop pinging, Watchog Timer will start counting down...\n");
		printf("...If the Watchdog Timer was enabled\n");

		/* Lets set a different handler for Ctrl+C */
		signal(SIGINT, pinghandler);

		ping = 1;
		while (ping) {
			if(ioctl(fd, WDIOC_KEEPALIVE, &dummy) < 0) {
				perror("Error sending ping");
				break;
			}
			sleep(1);
		}
	} else if (strncmp(cmdline, "gettimeout", 10) == 0) {
		int timeout;

		if(ioctl(fd, WDIOC_GETTIMEOUT, &timeout) < 0)
			perror("Error getting watchdog timeout");

		printf("\nCurrent setting of timeout is %d frequency units\n", timeout);
	} else if (strncmp(cmdline, "gettimeleft", 11) == 0) {
		int timeleft;

		if(ioctl(fd, WDIOC_GETTIMELEFT, &timeleft) < 0)
			perror("Error getting watchdog timeleft");

		printf("\nTime left for system reboot/shutdown is %d frequency units\n", timeleft);
	} else if (strncmp(cmdline, "sendmagicchar", 9) == 0) {
		printf("\nSending magic character to Watchdog device...\n");
		printf("\nWatchdog Timer will be stopped once you exit the application\n");
		if(write(fd, "V", 1) < 0)
			perror("Could not send magic character");
	} else if (strncmp(cmdline, "settimeout", 10) == 0) {
		const char *charp = cmdline;
		int timeout;

		/* Lets point to the end of first token */
		charp += strlen("settimeout");
		/* Skip blank characters */
		while (*charp == ' ' || *charp == '\t' || *charp == '\n')
			charp++;

		/* Now we should be pointing to the first 'digit' character */
		timeout = atoi(charp);

		if(ioctl(fd, WDIOC_SETTIMEOUT, &timeout) < 0) {
			perror("Could not set watchdog timeout");
			return;
		}

		printf("\nSetting timeout to %d frequency units\n", timeout);
		printf("Watchdog Timer will start counting down with the new timeout value\n");
	} else if (strncmp(cmdline, "license", 7) == 0) {
		show_license();
	} else {
		printf("\nUnknown command\n");
		print_usage();
	}
}

int main(void)
{
	char *cmdline= NULL;

	printf("Watchdog sample application version: %s\n", WATCHDOG_APP_VERSION);
	printf("Copyright (c) 2014, Advanced Micro Devices, Inc.\n"
	       "This sample application comes with ABSOLUTELY NO WARRANTY;\n"
	       "This is free software, and you are welcome to redistribute it\n"
	       "under certain conditions; type `license' for details.\n\n");


	if ((fd = open("/dev/watchdog", O_WRONLY)) < 0) {
		perror("Could not open /dev/watchdog");
		exit(1);
	}

	/* Handler for Ctrl+C */
	signal(SIGINT, sighandler);

	while (1) {
		cmdline = readline(show_prompt());
		parse_cmd(cmdline);
		/* Free the memory malloc'ed by readline */
		free(cmdline);
	}

	/* Should never reach here */
	return 0;
}
