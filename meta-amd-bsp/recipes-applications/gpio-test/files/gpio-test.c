/*****************************************************************************
*
* Copyright (c) 2017, Advanced Micro Devices, Inc.
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

#include <readline/readline.h>
#include <sys/types.h>
#include <sys/wait.h>
#include <sys/ioctl.h>

#include "gpio-test.h"

#define GPIO_APP_VERSION	"0.2"
#define AMD_GPIO_NUM_PINS	256
static int gpio_in_use[AMD_GPIO_NUM_PINS];

char *show_prompt(void)
{
	return "$ ";
}

void sighandler(int sig)
{
	printf("\n%s", show_prompt());
}

void show_license(void)
{
	printf("/*****************************************************************************\n"
	       "*\n"
	       "* Copyright (c) 2017, Advanced Micro Devices, Inc.\n"
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
	printf(" getgpiomode <gpio>			: Gets the mode of GPIO pin\n");
	printf(" setgpiomode <gpio> <in/out/high/low>	: Sets the mode of GPIO pin to input or output(high/low)\n");
	printf(" getgpiovalue <gpio>			: Gets the value of GPIO pin\n");
	printf(" setgpiovalue <gpio> <high/low>		: Sets the value of GPO pin to high or low\n");
	printf(" getnumgpio				: Gets the number of GPIO pins supported\n");
	printf(" getgpiobase				: Gets the number of first GPIO pin\n");
	printf(" getgpioname				: Gets the name of GPIO driver currently in use\n");
	printf(" dmesg					: Displays the kernel log messages related to GPIO\n");
	printf(" license				: Displays the terms of LICENSE for this application\n");
	printf(" help					: Displays help text\n");
	printf(" exit					: Exits the application\n\n");
}

void parse_cmd(const char *cmdline)
{
	int fd;

	if (strncmp(cmdline, "help", 4) == 0)
		print_usage();
	else if (strncmp(cmdline, "getnumgpio", 10) == 0) {
		int fd;
		char ngpio[3 + 1];

		memset(ngpio, '\0', (3 + 1));
		fd = open("/sys/class/gpio/gpiochip256/ngpio", O_RDONLY);
		if (fd < 0) {
			printf("\nPlease make sure AMD GPIO driver is loaded\n");
			exit(EXIT_FAILURE);
		}

		/* Value read from the file is ASCII text */
		if(read(fd, ngpio, 3) < 0)
			perror("Cannot read number of GPIO pins");

		printf("\nThe maximum number of GPIO pins supported is %d\n", atoi(ngpio));
		close(fd);
	} else if (strncmp(cmdline, "getgpiobase", 11) == 0) {
		int fd;
		char gpiobase[3 + 1];

		memset(gpiobase, '\0', (3 + 1));
		fd = open("/sys/class/gpio/gpiochip256/base", O_RDONLY);
		if (fd < 0) {
			printf("\nPlease make sure AMD GPIO driver is loaded\n");
			exit(EXIT_FAILURE);
		}

		if(read(fd, gpiobase, 3) < 0)
			perror("Cannot read GPIO base");

		printf("\nGPIO pin numbering starts from %d\n", atoi(gpiobase));
		close(fd);
	} else if (strncmp(cmdline, "getgpioname", 11) == 0) {
		int fd;
		char gpioname[10 + 1]; /* Max 10 characters + NULL character */

		/* Zero initialize gpioname array */
		memset(gpioname, '\0', sizeof(gpioname));

		fd = open("/sys/class/gpio/gpiochip256/label", O_RDONLY);
		if (fd < 0) {
			printf("\nPlease make sure AMD GPIO driver is loaded\n");
			exit(EXIT_FAILURE);
		}

		if(read(fd, gpioname, 10) < 0)
			perror("Cannot read GPIO driver name");

		printf("\nGPIO driver loaded is %s\n", gpioname);
		close(fd);
	} else if (strncmp(cmdline, "getgpiovalue", 12) == 0) {
		int fd;
		int gpio_num;
		char gpio[3 + 1];
		char pathname[80];
		int ret = 0;

		/* Lets point to the end of first token */
		if (sscanf(cmdline, "getgpiovalue %d", &gpio_num) < 1) {
			printf("Invalid inputs, please try again\n\n");
			return;
		}

		fd = open("/sys/class/gpio/export", O_WRONLY);
		if (fd < 0) {
			if (errno == EACCES)
				printf("\nYou do not have correct permission, please run as root\n");
			else
				perror("Error opening /sys/class/gpio/export");

			exit(EXIT_FAILURE);
		}

		memset(gpio, '\0', (3 + 1));
		if (snprintf(gpio, (3 + 1), "%d", gpio_num) < 1) {
			printf("Invalid inputs, please try again\n");
			close(fd);
			return;
		}

		ret = write(fd, gpio, strlen(gpio));
		/*
		 * There can be two situations ->
		 *      1) The GPIO is being exported for the first time.
		 *      2) The GPIO is being exported again.
		 * In the first case, the write to file descriptor should
		 * succeed, and we should still fall into the if clause.
		 *
		 * In the second case, write will fail and errno will be
		 * set to EBUSY, since the GPIO pin is already exported.
		 * Rest all is error.
		 */
		if((ret >= 0) || ((ret < 0) && (errno == EBUSY))) {
			/* Close the last file descriptor */
			close(fd);

			memset(pathname, '\0', sizeof(pathname));
			sprintf(pathname, "/sys/class/gpio/gpio%d/value", gpio_num);

			fd = open(pathname, O_RDONLY);
			if (fd < 0)
				perror("GPIO read error");
			else {
				char value[1 + 1];

				memset(value, '\0', 2);
				ret = read(fd, value, 1);
				if (ret < 0)
					perror("Cannot read GPIO pin");

				printf("\nGPIO pin %d is at \"%s\"\n", gpio_num,
				(strncmp(value, "1", 1) == 0) ? "high" : "low");

				close(fd);

				/*
				 * Mark the GPIO as already exported, so that we can use
				 * unexport them during exit.
				 */
				gpio_in_use[gpio_num] = 1;
			}
		} else {
			if (errno == EINVAL)
				printf("\nGPIO number is reserved\n");
			else
				perror("Error exporting GPIO number");

			close(fd);
		}
	} else if (strncmp(cmdline, "getgpiomode", 11) == 0) {
		int fd;
		int gpio_num;
		char gpio[3 + 1];
		char pathname[80];
		int ret = 0;

		/* Lets point to the end of first token */
		if (sscanf(cmdline, "getgpiomode %d", &gpio_num) < 1) {
			printf("Invalid inputs, please try again\n\n");
			return;
		}

		fd = open("/sys/class/gpio/export", O_WRONLY);
		if (fd < 0) {
			if (errno == EACCES)
				printf("\nYou do not have correct permission, please run as root\n");
			else
				perror("Error opening /sys/class/gpio/export");

			exit(EXIT_FAILURE);
		}

		memset(gpio, '\0', (3 + 1));
		if (snprintf(gpio, (3 + 1), "%d", gpio_num) < 1) {
			printf("Invalid inputs, please try again\n");
			close(fd);
			return;
		}

		ret = write(fd, gpio, strlen(gpio));
		/*
		 * There can be two situations ->
		 *      1) The GPIO is being exported for the first time.
		 *      2) The GPIO is being exported again.
		 * In the first case, the write to file descriptor should
		 * succeed, and we should still fall into the if clause.
		 *
		 * In the second case, write will fail and errno will be
		 * set to EBUSY, since the GPIO pin is already exported.
		 * Rest all is error.
		 */
		if((ret >= 0) || ((ret < 0) && (errno == EBUSY))) {
			/* Close the last file descriptor */
			close(fd);

			memset(pathname, '\0', sizeof(pathname));
			sprintf(pathname, "/sys/class/gpio/gpio%d/direction", gpio_num);

			fd = open(pathname, O_RDONLY);
			if (fd < 0)
				perror("GPIO read error");
			else {
				char mode[3 + 1];
				int c, i = 0;

				memset(mode, '\0', (3 + 1));
				ret = read(fd, mode, 3);
				if (ret < 0)
					perror("Cannot read GPIO pin");

				printf("\nGPIO pin %d is in \"%s\" mode\n", gpio_num,
				(strncmp(mode, "in", 2) == 0) ? "input" : "output");

				close(fd);

				/*
				 * Mark the GPIO as already exported, so that we can use
				 * unexport them during exit.
				 */
				gpio_in_use[gpio_num] = 1;
			}
		} else {
			if (errno == EINVAL)
				printf("\nGPIO number is reserved \n");
			else
				perror("Error exporting GPIO number");

			close(fd);
		}
	} else if (strncmp(cmdline, "setgpiomode", 11) == 0) {
		int fd;
		int gpio_num;
		char mode[3 + 1];
		char gpio[3 + 1];
		int ret;

		memset(mode, (3 + 1), 0);
		if (sscanf(cmdline, "setgpiomode %d %s", &gpio_num, mode) < 2) {
			printf("Invalid inputs, please try again\n\n");
			return;
		}

		memset(gpio, '\0', (3 + 1));
		if (snprintf(gpio, (3 + 1), "%d", gpio_num) < 1) {
			printf("Invalid inputs, please try again\n");
			return;
		}

		fd = open("/sys/class/gpio/export", O_WRONLY);
		if (fd < 0) {
			if (errno == EACCES)
				printf("\nYou do not have correct permission, please run as root\n");
			else
				perror("Error opening /sys/class/gpio/export");

			exit(EXIT_FAILURE);
		}

		ret = write(fd, gpio, strlen(gpio));
		if((ret >= 0) || ((ret < 0) && (errno == EBUSY))) {
			char pathname[80];

			/* Close the last file descriptor */
			close(fd);

			memset(pathname, '\0', sizeof(pathname));
			sprintf(pathname, "/sys/class/gpio/gpio%d/direction", gpio_num);

			fd = open(pathname, O_WRONLY);
			if (fd < 0)
				perror("GPIO read error");
			else {
				/* Sanity check */
				if ((strncmp(mode, "in", 2) == 0) ||
				    (strncmp(mode, "out", 3) == 0) ||
				    (strncmp(mode, "high", 4) == 0) ||
				    (strncmp(mode, "low", 3) == 0)) {
					/* Write mode into /sys/.../direction file */
					ret = write(fd, mode, strlen(mode));
					if (ret < 0)
						perror("Error writing GPIO mode");
				} else
					printf("\nInvalid GPIO mode, please try again\n");

				close(fd);

				/*
				 * Mark the GPIO as exported, so that we can use
				 * unexport them during exit.
				 */
				gpio_in_use[gpio_num] = 1;
			}
		} else {
			if (errno == EINVAL)
				printf("\nGPIO number is reserved\n");
			else
				perror("Error exporting GPIO number");

			close(fd);
		}
	} else if (strncmp(cmdline, "setgpiovalue", 12) == 0) {
		int fd;
		int gpio_num;
		char gpio[3 + 1];
		char value[4 + 1];
		int ret;

		memset(value, (4 + 1), 0);
		if (sscanf(cmdline, "setgpiovalue %d %s", &gpio_num, value) < 2) {
			printf("Invalid inputs, please try again\n\n");
			return;
		}

		memset(gpio, '\0', (3 + 1));
		if (snprintf(gpio, (3 + 1), "%d", gpio_num) < 1) {
			printf("Invalid inputs, please try again\n");
			return;
		}

		fd = open("/sys/class/gpio/export", O_WRONLY);
		if (fd < 0) {
			if (errno == EACCES)
				printf("\nYou do not have correct permission, please run as root\n");
			else
				perror("Error opening /sys/class/gpio/export");

			exit(EXIT_FAILURE);
		}

		ret = write(fd, gpio, strlen(gpio));
		if((ret >= 0) || ((ret < 0) && (errno == EBUSY))) {
			char pathname[80];

			/* Close the last file descriptor */
			close(fd);

			memset(pathname, '\0', sizeof(pathname));
			sprintf(pathname, "/sys/class/gpio/gpio%d/value", gpio_num);

			fd = open(pathname, O_WRONLY);
			if (fd < 0)
				perror("GPIO read error");
			else {
				if (strncmp(value, "high", 4) == 0)
					value[0] = '1';
				else if (strncmp(value, "low", 3) == 0)
					value[0] = '0';
				else {
					printf("\nInvalid input, please try again...\n");
					return;
				}

				/* Write mode into /sys/.../direction file */
				ret = write(fd, value, 1);
				if (ret < 0)
					perror("Error writing GPIO mode");

				close(fd);

				/*
				 * Mark the GPIO as exported, so that we can use
				 * unexport them during exit.
				 */
				gpio_in_use[gpio_num] = 1;
			}
		} else {
			if (errno == EINVAL)
				printf("\nGPIO number is reserved\n");
			else
				perror("Error exporting GPIO number");

			close(fd);
		}
	} else if (strncmp(cmdline, "dmesg", 5) == 0) {
		if (system("dmesg | grep GPIO") < 0)
			perror("Error executing \'dmesg | grep GPIO\'");
	} else if (strncmp(cmdline, "license", 7) == 0) {
		show_license();
	} else if (strncmp(cmdline, "exit", 4) == 0) {
		int i;
		int ret;
		char gpio[3 + 1];
		printf("\nExiting...\n");
		for (i = 0; i < AMD_GPIO_NUM_PINS; i++) {
			if (gpio_in_use[i]) {
				int fd;
				fd = open("/sys/class/gpio/unexport", O_WRONLY);
				if (fd < 0) {
					printf("\nPlease make sure AMD GPIO driver is loaded\n");
					exit(EXIT_FAILURE);
				}
				memset(gpio, '\0', (3 + 1));
				snprintf(gpio, (3 + 1), "%d", i);
				ret = write(fd, gpio, strlen(gpio));
				if (ret < 0)
					perror("Error writing to /sys/class/gpio/unexport");
			}
		}
		exit(EXIT_SUCCESS);
	} else {
		printf("\nUnknown command\n");
		print_usage();
	}
}

int main(void)
{
	char *cmdline= NULL;

	printf("GPIO sample application version: %s\n", GPIO_APP_VERSION);
	printf("Copyright (c) 2017, Advanced Micro Devices, Inc.\n"
	       "This sample application comes with ABSOLUTELY NO WARRANTY;\n"
	       "This is free software, and you are welcome to redistribute it\n"
	       "under certain conditions; type `license' for details.\n\n");

	/* Handler for Ctrl+C */
	signal(SIGINT, sighandler);

	while (1) {
		cmdline = readline(show_prompt());
		parse_cmd(cmdline);
		/* Free the memory malloc'ed by readline */
		free(cmdline);
		cmdline = NULL;
	}

	/* Should never reach here */
	return 0;
}
