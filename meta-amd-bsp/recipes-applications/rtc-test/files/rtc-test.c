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
#include <unistd.h>
#include <stdio.h>
#include <stdlib.h>
#include <fcntl.h>
#include <signal.h>
#include <errno.h>
#include <string.h>
#include <linux/rtc.h>

#include <readline/readline.h>
#include <sys/types.h>
#include <sys/wait.h>
#include <sys/ioctl.h>

#define RTC_APP_VERSION	"0.1"
static const char *rtc = "/dev/rtc0";
static int rtc_fd;
static int signal_recvd;
static volatile int loop;

char *show_prompt(void)
{
	return "$ ";
}

void sighandler(int sig)
{
	printf("\n%s", show_prompt());
}

void periodicinthandler(int sig)
{
	int ret;

	fprintf(stderr, "\nAborting...\n");
	fflush(stderr);

	loop = 0;

	/* Turn off periodic interrupts */
	ret = ioctl(rtc_fd, RTC_PIE_OFF, 0);
	if (ret == -1)
		perror("RTC_PIE_OFF ioctl");

	/* Restore original handler for SIGINT */
	signal(SIGINT, sighandler);
}

void updateinthandler(int sig)
{
	int ret;

	fprintf(stderr, "\nAborting...\n");
	fflush(stderr);

	loop = 0;

	/* Turn off update interrupt */
	ret = ioctl(rtc_fd, RTC_UIE_OFF, 0);
	if (ret == -1)
		perror("RTC_UIE_OFF ioctl");

	/* Restore original handler for SIGINT */
	signal(SIGINT, sighandler);
}

void alarminthandler(int sig)
{
	struct rtc_wkalrm rtc_wakealarm;
	int ret;

	signal_recvd = 1;

	ret = ioctl(rtc_fd, RTC_WKALM_RD, &rtc_wakealarm);
	if (ret == -1) {
		perror("RTC_WKALM_RD ioctl");
		return;
	}

	/* disable alarm and set pending to 0 */
	rtc_wakealarm.enabled = 0;
	rtc_wakealarm.pending = 0;

	ret = ioctl(rtc_fd, RTC_WKALM_SET, &rtc_wakealarm);
	if (ret == -1) {
		perror("RTC_WKALM_SET ioctl");
		return;
	}

	/* Restore original handler for SIGINT */
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

void print_usage(void)
{
	printf("\nCommands Supported ->\n");
	printf(" updateinton				: Turns on update interrupt\n");
	printf(" updateintoff				: Turns off update interrupt\n");
	printf(" getrtctime				: Reads the current RTC time\n");
	printf(" setrtctime <date>, <time>		: Sets RTC date and time. Both date and time are mandatory\n");
	printf(" getwakealarm				: Reads the current alarm setting\n");
	printf(" setwakealarm <date>, <time>		: Sets the alarm date and time. Both date and time are mandatory\n");
	printf(" wakealarmoff				: Turn off wakeup alarm set previously\n");
	printf(" getperiodicrate			: Reads the current periodic interrupt rate\n");
	printf(" setperiodicrate <rate>			: Sets the periodic interrupt rate\n");
	printf("					: The rate can take values from 2 to 8192 in steps of "
		"power of 2\n");
	printf("					: 2, 4, 8, ..., 8192\n");
	printf(" periodicinton				: Turns on periodic interrupt\n");
	printf(" periodicintoff				: Turns off periodic interrupt\n");
	printf(" license				: Displays the terms of LICENSE for this application\n");
	printf(" help					: Displays help text\n");
	printf(" exit					: Exits the application\n\n");
}

void parse_cmd(const char *cmdline)
{
	int ret, irqcount = 0;
	unsigned long data;
	struct rtc_time rtc_time;
	struct rtc_wkalrm rtc_wakealarm;

	if ((cmdline == NULL) || (strncmp(cmdline, "exit", 4) == 0)) {
		close(rtc_fd);
		printf("\nExiting...\n");
		exit(EXIT_SUCCESS);
	} else if (strncmp(cmdline, "help", 4) == 0)
		print_usage();
	else if (strncmp(cmdline, "updateinton", 11) == 0) {
		int i;
		
		ret = ioctl(rtc_fd, RTC_UIE_ON, 0);
		if (ret == -1) {
			if (errno == ENOTTY)
				fprintf(stderr, "\n..Update interrupt not supported.\n");

			perror("RTC_UIE_ON ioctl");
			return;
		}

		fprintf(stderr, "Counting update interrupts by reading %s...Press Ctrl+C to abort\n", rtc);
		fflush(stderr);

		/* Set default handler for SIGINT */
		signal(SIGINT, updateinthandler);

		i = loop = 1;
		while (loop) {
			struct timeval tv = {5, 0};
			fd_set readfds;

			FD_ZERO(&readfds);
			FD_SET(rtc_fd, &readfds);

			ret = select(rtc_fd + 1, &readfds, NULL, NULL, &tv);
			if (ret == -1) {
				if (errno != EINTR)
					perror("select");

				/* Break the loop */
				loop = 0;
			} else {
				/* Non blocking read */
				ret = read(rtc_fd, &data, sizeof(unsigned long));
				if (ret == -1) {
					perror("read");
					loop = 0;
				} else {
					fprintf(stderr, " %d", i++);
					irqcount++;
				}
			}
		}

		/* Turn off update interrupt */
		ret = ioctl(rtc_fd, RTC_UIE_OFF, 0);
		if (ret == -1)
			perror("RTC_UIE_OFF ioctl");
	} else if (strncmp(cmdline, "updateintoff", 12) == 0) {
		fprintf(stderr, "Turning update interrupt off\n");
		fflush(stderr);

		ret = ioctl(rtc_fd, RTC_UIE_OFF, 0);
		if (ret == -1)
			perror("RTC_UIE_OFF ioctl");
	} else if (strncmp(cmdline, "getrtctime", 10) == 0) {
		ret = ioctl(rtc_fd, RTC_RD_TIME, &rtc_time);
		if (ret == -1)
			perror("RTC_RD_TIME ioctl");
		else
			fprintf(stderr, "\nCurrent RTC date and time is %02d/%02d/%04d, %02d:%02d:%02d\n",
				rtc_time.tm_mon + 1, rtc_time.tm_mday, rtc_time.tm_year + 1900,
				rtc_time.tm_hour, rtc_time.tm_min, rtc_time.tm_sec);
	} else if (strncmp(cmdline, "setrtctime", 10) == 0) {
		/* Point past the string and one whitespace */
		cmdline += 11;
		ret = sscanf(cmdline, "%02d/%02d/%04d, %02d:%02d:%02d", &rtc_time.tm_mon, &rtc_time.tm_mday,
			     &rtc_time.tm_year, &rtc_time.tm_hour, &rtc_time.tm_min, &rtc_time.tm_sec);

		if (ret < 6) {
			fprintf(stderr, "\nPlease check your input\n");
			return;
		}

		/* months should be in the range 0 to 11 */
		rtc_time.tm_mon -= 1;
		/* years should be number of years since 1900 */
		rtc_time.tm_year -= 1900;
		ret = ioctl(rtc_fd, RTC_SET_TIME, &rtc_time);
		if (ret == -1)
			perror("RTC_SET_TIME ioctl");
	} else if (strncmp(cmdline, "getwakealarm", 12) == 0) {
		ret = ioctl(rtc_fd, RTC_WKALM_RD, &rtc_wakealarm);
		if (ret == -1)
			perror("RTC_WKALM_RD ioctl");
		else {
			fprintf(stderr, "\nRTC alarm is %s and %s\n",
				rtc_wakealarm.enabled ? "enabled" : "disabled",
				rtc_wakealarm.pending ? "pending": "not pending");
			fprintf(stderr, "\nCurrent alarm date and time is %02d/%02d/%04d, %02d:%02d:%02d\n",
				rtc_wakealarm.time.tm_mon + 1, rtc_wakealarm.time.tm_mday,
				rtc_wakealarm.time.tm_year + 1900, rtc_wakealarm.time.tm_hour,
				rtc_wakealarm.time.tm_min, rtc_wakealarm.time.tm_sec);
		}
	} else if (strncmp(cmdline, "setwakealarm", 12) == 0) {
		fprintf(stderr, "\nSetting alarm interrupt...Press Ctrl+C to abort\n\n");
		fflush(stderr);

		/* Point past the string and one whitespace */
		cmdline += 13;
		ret = sscanf(cmdline, "%02d/%02d/%04d, %02d:%02d:%02d",
			     &rtc_wakealarm.time.tm_mon, &rtc_wakealarm.time.tm_mday,
			     &rtc_wakealarm.time.tm_year, &rtc_wakealarm.time.tm_hour,
			     &rtc_wakealarm.time.tm_min, &rtc_wakealarm.time.tm_sec);

		if (ret < 6) {
			fprintf(stderr, "\nPlease check your input\n");
			return;
		}

		/* months should be in the range 0 to 11 */
		rtc_wakealarm.time.tm_mon -= 1;
		/* years should be number of years since 1900 */
		rtc_wakealarm.time.tm_year -= 1900;

		/* Enable wake alarm interrupt */
		rtc_wakealarm.enabled = 1;

		/* Set pending to 0 */
		rtc_wakealarm.pending = 1;

		/* Set handler for SIGINT */
		signal(SIGINT, alarminthandler);

		ret = ioctl(rtc_fd, RTC_WKALM_SET, &rtc_wakealarm);
		if (ret == -1) {
			perror("RTC_WKALM_SET ioctl");
			return;
		}

		while (1) {
			ret = ioctl(rtc_fd, RTC_WKALM_RD, &rtc_wakealarm);
			if (ret == -1) {
				perror("RTC_WKALM_RD ioctl");
				return;
			}

			if (!rtc_wakealarm.enabled) {
				/* We could be here either because we received the alarm
				 * interrupt, or the SIGINT handler was executed. To
				 * differentiate between the two cases, we use the flag.
				 */
				if (!signal_recvd)
					fprintf(stderr, "\nReceived alarm interrupt\n");
				else
					fprintf(stderr, "\nAborting...\n");

				fflush(stderr);
				break;
			}
		}

		/* In case we did not receive a signal, and we fall through */
		alarminthandler(SIGINT);
		signal_recvd = 0;
	} else if (strncmp(cmdline, "wakealarmoff", 12) == 0) {
		fprintf(stderr, "Turning wake alarm interrupt off\n");
		fflush(stderr);

		ret = ioctl(rtc_fd, RTC_WKALM_RD, &rtc_wakealarm);
		if (ret == -1) {
			perror("RTC_WKALM_RD ioctl");
			return;
		}

		/* Disable wake alarm */
		rtc_wakealarm.enabled = 0;
		rtc_wakealarm.pending = 0;
		ret = ioctl(rtc_fd, RTC_WKALM_SET, &rtc_wakealarm);

		if (ret == -1)
			perror("RTC_WKALM_SET ioctl");
	} else if (strncmp(cmdline, "getperiodicrate", 15) == 0) {
		unsigned long rate;

		ret = ioctl(rtc_fd, RTC_IRQP_READ, &rate);
		if (ret == -1) {
			if (errno == ENOTTY)
				fprintf(stderr, "\nNo periodic interrupt support\n");
			else
				perror("RTC_IRQP_READ ioctl");

			return;
		}

		fprintf(stderr, "\nPeriodic interrupt rate is %luHz\n", rate);
	} else if (strncmp(cmdline, "setperiodicrate", 15) == 0) {
		unsigned long rate;

		cmdline += 16;

		sscanf(cmdline, "%lu", &rate);
		/* bounds check */
		if (rate < 2 || rate > 8192) {
			fprintf(stderr, "\nInvalid rate specified\n");
			return;
		}

		/* the rate should be a power of 2 */
		if (rate & (rate - 1)) {
			fprintf(stderr, "\nInvalid rate. Only power of 2 allowed\n");
			return;
		}

		ret = ioctl(rtc_fd, RTC_IRQP_SET, rate);
		if (ret == -1) {
			if (errno == ENOTTY)
				fprintf(stderr, "\nCannot change periodic interrupt rate\n");
			else
				perror("RTC_IRQP_SET ioctl");

			return;
		}
	} else if (strncmp(cmdline, "periodicinton", 13) == 0) {
		/* Set default handler for SIGINT */
		signal(SIGINT, periodicinthandler);

		ret = ioctl(rtc_fd, RTC_PIE_ON, 0);
		if (ret == -1) {
			perror("RTC_PIE_ON ioctl");
			return;
		}

		fprintf(stderr, "\nChecking periodic interrupt rate...Press Ctrl+C to abort\n\n");
		fflush(stderr);

		loop = 1;
		while (loop) {
			struct timeval tv = {5, 0};
			fd_set readfds;

			FD_ZERO(&readfds);
			FD_SET(rtc_fd, &readfds);

			ret = select(rtc_fd + 1, &readfds, NULL, NULL, &tv);
			if (ret == -1) {
				if (errno != EINTR)
					perror("select");

				/* Break the loop */
				loop = 0;
			} else {
				/* Non blocking read */
				ret = read(rtc_fd, &data, sizeof(unsigned long));
				if (ret == -1) {
					perror("read");
					loop = 0;
				} else {
					fprintf(stderr, ".");
					irqcount++;
				}
			}
		}

		/* Turn off periodic interrupts */
		ret = ioctl(rtc_fd, RTC_PIE_OFF, 0);
		if (ret == -1)
			perror("RTC_PIE_OFF ioctl");
	} else if (strncmp(cmdline, "periodicintoff", 14) == 0) {
		fprintf(stderr, "Turning periodic interrupt off\n");
		fflush(stderr);

		ret = ioctl(rtc_fd, RTC_PIE_OFF, 0);
		if (ret == -1)
			perror("RTC_PIE_OFF ioctl");
	} else if (strncmp(cmdline, "license", 7) == 0) {
		show_license();
	} else {
		printf("\nUnknown command\n");
		print_usage();
	}
}

int main(int argc, char *argv[])
{
	char *cmdline= NULL;

	printf("RTC sample application version: %s\n", RTC_APP_VERSION);
	printf("Copyright (c) 2014, Advanced Micro Devices, Inc.\n"
	       "This sample application comes with ABSOLUTELY NO WARRANTY;\n"
	       "This is free software, and you are welcome to redistribute it\n"
	       "under certain conditions; type `license' for details.\n\n");

	/* Handler for Ctrl+C */
	signal(SIGINT, sighandler);

	switch(argc) {
	case 2:
		rtc = argv[1];
		/* FALL THROUGH */
	case 1:
		break;
	default:
		fprintf(stderr, "usage: rtc_test [rtcdev]\n");
		return 1;
	}

	rtc_fd = open(rtc, O_RDONLY);
	if (rtc_fd == -1) {
		perror(rtc);
		exit(errno);
	}

	while (1) {
		cmdline = readline(show_prompt());
		parse_cmd(cmdline);
		/* Free the memory malloc'ed by readline */
		free(cmdline);
	}

	/* Should never reach here */
	return 0;
}
