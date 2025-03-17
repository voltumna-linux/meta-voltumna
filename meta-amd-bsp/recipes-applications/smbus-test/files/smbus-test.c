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
#include <dirent.h>

#include <sys/types.h>
#include <sys/ioctl.h>
#include <sys/stat.h>

#include <readline/readline.h>

#include "i2c-dev.h"

#define SMBUS_APP_VERSION "0.1"

static int adapter_nr = -1;
static int slave_addr = 0xFF;
static char filename[20];
static int fd = -1;

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
	printf(" enumerate				: List all adapters available\n");
	printf(" setadapternum <num>			: Set the adapter number\n");
	printf(" getadapternum				: Get the current adapter number\n");
	printf(" setslaveaddr <addr>			: Set the slave device address\n");
	printf(" getslaveaddr				: Get the current slave device address\n");
	printf(" getadapterfunc				: Displays the functionalities supported by the adapter\n");
	printf(" quicksend <bit>			: Sends a single bit (0 or 1) to the device\n");
	printf(" receivebyte				: Receive a single byte from the slave device\n");
	printf(" sendbyte <byte>			: Sends a single byte to the slave device\n");
	printf(" readbyte <register>			: Reads a byte at register of the slave device\n");
	printf(" writebyte <register> <byte>		: Writes a byte at register of the slave device\n");
	printf(" readword <register>			: Reads a word at register of the slave device\n");
	printf(" writeword <register> <word>		: Writes a word at register of the slave device\n");
	printf(" readblock <register>			: Reads a block of data from register of the slave device\n");
	printf(" writeblock <register> <filename>	: Writes a block of data read from filename to register\n"
	       "                                          of the slave device\n");
	printf(" license				: Displays the terms of LICENSE for this application\n");
	printf(" help					: Displays help text\n");
	printf(" exit					: Exits the application\n\n");
}

void parse_cmd(const char *cmdline)
{
	struct i2c_smbus_ioctl_data param;
	union i2c_smbus_data smbus_data;
	unsigned long funcs;

	if ((cmdline == NULL) || (strncmp(cmdline, "exit", 4) == 0)) {
		printf("\nExiting...\n");
		if((fd != -1) && (close(fd) < 0))
			printf("Error closing device\n\n");

		exit(EXIT_SUCCESS);
	} else if (strncmp(cmdline, "enumerate", 9) == 0) {
		DIR *dir;
		struct dirent *dir_entry;
		int adapter_found = 0;

		/* Get the directory handle */
		if ((dir = opendir("/dev")) == NULL) {
			printf("Failed to open directory /dev. Probably you "
			       "do not have right privilege!\n\n");
			exit(EXIT_FAILURE);
		}

		/* Iterate over all the directory entries */
		while ((dir_entry = readdir(dir)) != NULL) {
			/*
			 * If the file is a character device, and its signature
			 * matches i2c-x, then we print the corresponding file.
			 */
			if ((dir_entry->d_type == DT_CHR) &&
			    (strncmp(dir_entry->d_name, "i2c-", 4) == 0)) {
				printf("%s\n", dir_entry->d_name);
				adapter_found = 1;
			}
		}

		printf("\n");

		/*
		 * In case we did not find even a single adapter, we print a
		 * message and exit.
		 */
		if (!adapter_found) {
			printf("No adapters found, load i2c-dev kernel module and try again\n\n");
			exit(EXIT_FAILURE);
		}
	} else if (strncmp(cmdline, "setadapternum", 13) == 0) {
		int input;
		int file_desc;

		cmdline += 14;
		if (sscanf(cmdline, "%d", &input) < 1) {
			printf("Invalid inputs, please try again\n\n");
			return;
		}

		snprintf(filename, 19, "/dev/i2c-%d", input);
		file_desc = open(filename, O_RDWR);
		if (file_desc < 0) {
			printf("Error opening file %s\n\n", filename);
			return;
		}

		/* Once we have validated inputs, we store them into the global
		 * variables used at other places in the program.
		 */
		fd = file_desc;
		adapter_nr = input;
		printf("Adapter Number set to %d\n\n", adapter_nr);
	} else if (strncmp(cmdline, "getadapternum", 13) == 0) {
		if (adapter_nr == -1)
			printf("Adapter Number not set\n\n");
		else
			printf("Adapter Number set to %d\n\n", adapter_nr);
	} else if (strncmp(cmdline, "setslaveaddr", 12) == 0) {
		int addr;

		cmdline += 13;
		if (sscanf(cmdline, "0x%x", &addr) < 1) {
			printf("Invalid inputs, please try again\n\n");
			return;
		}

		/* Set the slave address */
		if (ioctl(fd, I2C_SLAVE, addr) < 0) {
			printf("Error setting slave address. Please make sure "
			       "to provide 7-bit slave address\n\n");
			return;
		}

		slave_addr = addr;
		printf("Slave Address set to 0x%x\n\n", slave_addr);
	} else if (strncmp(cmdline, "getslaveaddr", 12) == 0) {
		if (slave_addr == 0xFF)
			printf("Slave Address not set\n\n");
		else
			printf("Slave Address set to 0x%x\n\n", slave_addr);
	} else if (strncmp(cmdline, "getadapterfunc", 14) == 0) {
		if (adapter_nr == -1) {
			printf("Please set adapter first\n\n");
			return;
		}

		/* Get the adapter functionality */
		if (ioctl(fd, I2C_FUNCS, &funcs) < 0) {
			printf("Error getting adapter functionalities\n\n");
			return;
		}

		if (funcs & I2C_FUNC_I2C)
			printf("I2C_FUNC_I2C\n");
		if (funcs & I2C_FUNC_10BIT_ADDR)
			printf("I2C_FUNC_10BIT_ADDR\n");
		if (funcs & I2C_FUNC_PROTOCOL_MANGLING)
			printf("I2C_FUNC_PROTOCOL_MANGLING\n");
		if (funcs & I2C_FUNC_SMBUS_PEC)
			printf("I2C_FUNC_SMBUS_PEC\n");
		if (funcs & I2C_FUNC_SMBUS_BLOCK_PROC_CALL)
			printf("I2C_FUNC_SMBUS_BLOCK_PROC_CALL\n");
		if (funcs & I2C_FUNC_SMBUS_QUICK)
			printf("I2C_FUNC_SMBUS_QUICK\n");
		if (funcs & I2C_FUNC_SMBUS_READ_BYTE)
			printf("I2C_FUNC_SMBUS_READ_BYTE\n");
		if (funcs & I2C_FUNC_SMBUS_WRITE_BYTE)
			printf("I2C_FUNC_SMBUS_WRITE_BYTE\n");
		if (funcs & I2C_FUNC_SMBUS_READ_BYTE_DATA)
			printf("I2C_FUNC_SMBUS_READ_BYTE_DATA\n");
		if (funcs & I2C_FUNC_SMBUS_WRITE_BYTE_DATA)
			printf("I2C_FUNC_SMBUS_WRITE_BYTE_DATA\n");
		if (funcs & I2C_FUNC_SMBUS_READ_WORD_DATA)
			printf("I2C_FUNC_SMBUS_READ_WORD_DATA\n");
		if (funcs & I2C_FUNC_SMBUS_WRITE_WORD_DATA)
			printf("I2C_FUNC_SMBUS_WRITE_WORD_DATA\n");
		if (funcs & I2C_FUNC_SMBUS_PROC_CALL)
			printf("I2C_FUNC_SMBUS_PROC_CALL\n");
		if (funcs & I2C_FUNC_SMBUS_READ_BLOCK_DATA)
			printf("I2C_FUNC_SMBUS_READ_BLOCK_DATA\n");
		if (funcs & I2C_FUNC_SMBUS_WRITE_BLOCK_DATA)
			printf("I2C_FUNC_SMBUS_WRITE_BLOCK_DATA\n");
		if (funcs & I2C_FUNC_SMBUS_READ_I2C_BLOCK)
			printf("I2C_FUNC_SMBUS_READ_I2C_BLOCK\n");
		if (funcs & I2C_FUNC_SMBUS_WRITE_I2C_BLOCK)
			printf("I2C_FUNC_SMBUS_WRITE_I2C_BLOCK\n");

		printf("\n");
	} else if (strncmp(cmdline, "quicksend", 9) == 0) {
		int bit;

		/* Get the adapter functionality */
		if (ioctl(fd, I2C_FUNCS, &funcs) < 0) {
			printf("Error getting adapter functionalities\n\n");
			return;
		}

		if (!(funcs & I2C_FUNC_SMBUS_QUICK)) {
			printf("SMBus Quick command not supported by the adapter\n\n");
			return;
		}

		cmdline += 10;
		if (sscanf(cmdline, "%d", &bit) < 1) {
			printf("Invalid input, please try again\n\n");
			return;
		}

		/* Sanity check */
		if ((bit != 0) && (bit != 1)) {
			printf("Only 0 or 1 is allowed\n\n");
			return;
		}

		memset(&param, 0, sizeof(struct i2c_smbus_ioctl_data));
		param.data = NULL;

		if (bit)
			param.read_write = I2C_SMBUS_READ;
		else
			param.read_write = I2C_SMBUS_WRITE;

		param.size = I2C_SMBUS_QUICK;
		if (ioctl(fd, I2C_SMBUS, &param) == -1) {
			printf("SMBus Quick command failed\n\n");
			return;
		}

		printf("Quick Send %d successfull\n\n", bit);
	} else if (strncmp(cmdline, "receivebyte", 11) == 0) {
		/* Get the adapter functionality */
		if (ioctl(fd, I2C_FUNCS, &funcs) < 0) {
			printf("Error getting adapter functionalities\n\n");
			return;
		}

		if (!(funcs & I2C_FUNC_SMBUS_BYTE)) {
			printf("SMBus receivebyte command not supported by adapter\n");
			return;
		}

		memset(&param, 0, sizeof(struct i2c_smbus_ioctl_data));
		memset(&smbus_data, 0, sizeof(union i2c_smbus_data));
		param.data = &smbus_data;

		param.read_write = I2C_SMBUS_READ;
		param.size = I2C_SMBUS_BYTE;
		if (ioctl(fd, I2C_SMBUS, &param) == -1) {
			printf("SMBus Receive Byte command failed\n\n");
			return;
		}

		printf("Byte Received 0x%x\n\n", param.data->byte);
	} else if (strncmp(cmdline, "sendbyte", 8) == 0) {
		int byte;

		/* Get the adapter functionality */
		if (ioctl(fd, I2C_FUNCS, &funcs) < 0) {
			printf("Error getting adapter functionalities\n\n");
			return;
		}

		if (!(funcs & I2C_FUNC_SMBUS_BYTE)) {
			printf("SMBus sendbyte command not supported by adapter\n");
			return;
		}

		cmdline += 9;
		if (sscanf(cmdline, "0x%x", &byte) < 1) {
			printf("Invalid inputs, please try again\n\n");
			return;
		}

		memset(&param, 0, sizeof(struct i2c_smbus_ioctl_data));
		param.data = NULL;

		param.read_write = I2C_SMBUS_WRITE;
		param.command = byte;
		param.size = I2C_SMBUS_BYTE;
		if (ioctl(fd, I2C_SMBUS, &param) == -1) {
			printf("SMBus Send Byte command failed\n\n");
			return;
		}

		printf("Sent 0x%x to slave\n\n", byte);
	} else if (strncmp(cmdline, "readbyte", 8) == 0) {
		int reg;

		/* Get the adapter functionality */
		if (ioctl(fd, I2C_FUNCS, &funcs) < 0) {
			printf("Error getting adapter functionalities\n\n");
			return;
		}

		if (!(funcs & I2C_FUNC_SMBUS_BYTE_DATA)) {
			printf("SMBus readbyte command not supported by adapter\n");
			return;
		}

		cmdline += 9;
		if (sscanf(cmdline, "0x%x", &reg) < 1) {
			printf("Invalid inputs, please try again\n\n");
			return;
		}

		memset(&param, 0, sizeof(struct i2c_smbus_ioctl_data));
		memset(&smbus_data, 0, sizeof(union i2c_smbus_data));
		param.data = &smbus_data;

		param.command = reg;
		param.read_write = I2C_SMBUS_READ;
		param.size = I2C_SMBUS_BYTE_DATA;
		if (ioctl(fd, I2C_SMBUS, &param) == -1) {
			printf("SMBus Read Byte Data command failed\n\n");
			return;
		}

		printf("Read 0x%x at register 0x%x of the slave\n\n", param.data->byte, reg);
	} else if (strncmp(cmdline, "writebyte", 9) == 0) {
		int reg, byte;

		/* Get the adapter functionality */
		if (ioctl(fd, I2C_FUNCS, &funcs) < 0) {
			printf("Error getting adapter functionalities\n\n");
			return;
		}

		if (!(funcs & I2C_FUNC_SMBUS_BYTE_DATA)) {
			printf("SMBus writebyte command not supported by adapter\n");
			return;
		}

		cmdline += 10;
		if (sscanf(cmdline, "0x%x 0x%x", &reg, &byte) < 2) {
			printf("Invalid inputs, please try again\n\n");
			return;
		}

		memset(&param, 0, sizeof(struct i2c_smbus_ioctl_data));
		memset(&smbus_data, 0, sizeof(union i2c_smbus_data));
		param.data = &smbus_data;

		param.command = reg;
		param.read_write = I2C_SMBUS_WRITE;
		param.size = I2C_SMBUS_BYTE_DATA;
		param.data->byte = byte;
		if (ioctl(fd, I2C_SMBUS, &param) == -1) {
			printf("SMBus Write Byte Data command failed\n\n");
			return;
		}

		printf("Written 0x%x to register 0x%x of the slave\n\n", byte, reg);
	} else if (strncmp(cmdline, "readword", 8) == 0) {
		int reg;

		/* Get the adapter functionality */
		if (ioctl(fd, I2C_FUNCS, &funcs) < 0) {
			printf("Error getting adapter functionalities\n\n");
			return;
		}

		if (!(funcs & I2C_FUNC_SMBUS_WORD_DATA)) {
			printf("SMBus readword command not supported by adapter\n");
			return;
		}

		cmdline += 9;
		if (sscanf(cmdline, "0x%x", &reg) < 1) {
			printf("Invalid inputs, please try again\n\n");
			return;
		}

		memset(&param, 0, sizeof(struct i2c_smbus_ioctl_data));
		memset(&smbus_data, 0, sizeof(union i2c_smbus_data));
		param.data = &smbus_data;

		param.command = reg;
		param.read_write = I2C_SMBUS_READ;
		param.size = I2C_SMBUS_WORD_DATA;
		if (ioctl(fd, I2C_SMBUS, &param) == -1) {
			printf("SMBus Read Word Data command failed\n\n");
			return;
		}

		printf("Read 0x%.4x at register 0x%x of the slave\n\n", param.data->word, reg);
	} else if (strncmp(cmdline, "writeword", 9) == 0) {
		int reg, word;

		/* Get the adapter functionality */
		if (ioctl(fd, I2C_FUNCS, &funcs) < 0) {
			printf("Error getting adapter functionalities\n\n");
			return;
		}

		if (!(funcs & I2C_FUNC_SMBUS_WORD_DATA)) {
			printf("SMBus writeword command not supported by adapter\n");
			return;
		}

		cmdline += 10;
		if (sscanf(cmdline, "0x%x 0x%x", &reg, &word) < 2) {
			printf("Invalid inputs, please try again\n\n");
			return;
		}

		memset(&param, 0, sizeof(struct i2c_smbus_ioctl_data));
		memset(&smbus_data, 0, sizeof(union i2c_smbus_data));
		param.data = &smbus_data;

		param.command = reg;
		param.read_write = I2C_SMBUS_WRITE;
		param.size = I2C_SMBUS_WORD_DATA;
		param.data->word = word;
		if (ioctl(fd, I2C_SMBUS, &param) == -1) {
			printf("SMBus Write Word Data command failed\n\n");
			return;
		}

		printf("Written 0x%x to register 0x%x of the slave\n\n", word, reg);
	} else if (strncmp(cmdline, "readblock", 9) == 0) {
		int reg;
		int i;

		/* Get the adapter functionality */
		if (ioctl(fd, I2C_FUNCS, &funcs) < 0) {
			printf("Error getting adapter functionalities\n\n");
			return;
		}

		if (!(funcs & I2C_FUNC_SMBUS_BLOCK_DATA)) {
			printf("SMBus readblock command not supported by adapter\n");
			return;
		}

		cmdline += 10;
		if (sscanf(cmdline, "0x%x", &reg) < 1) {
			printf("Invalid inputs, please try again\n\n");
			return;
		}

		memset(&param, 0, sizeof(struct i2c_smbus_ioctl_data));
		memset(&smbus_data, 0, sizeof(union i2c_smbus_data));
		param.data = &smbus_data;

		param.command = reg;
		param.read_write = I2C_SMBUS_READ;
		param.size = I2C_SMBUS_BLOCK_DATA;
		if (ioctl(fd, I2C_SMBUS, &param) == -1) {
			printf("SMBus Read Block Data command failed\n\n");
			return;
		}

		printf("Reading %d bytes from register 0x%x:\n", param.data->block[0], reg);
		for (i = 1; i <= param.data->block[0]; i++)
			printf("0x%.2x ", param.data->block[i]);
		printf("\n\n");
	} else if (strncmp(cmdline, "writeblock", 10) == 0) {
		int reg;
		char infile[256];
		FILE *file;
		int data;
		int num_bytes = 0;
		int i;

		/* Get the adapter functionality */
		if (ioctl(fd, I2C_FUNCS, &funcs) < 0) {
			printf("Error getting adapter functionalities\n\n");
			return;
		}

		if (!(funcs & I2C_FUNC_SMBUS_BLOCK_DATA)) {
			printf("SMBus writeblock command not supported by adapter\n");
			return;
		}

		cmdline += 11;
		if (sscanf(cmdline, "0x%x %s", &reg, infile) < 2) {
			printf("Invalid inputs, please try again\n\n");
			return;
		}

		/* open infile for reading */
		if ((file = fopen(infile, "r")) == NULL) {
			printf("Failed to open file %s\n\n", infile);
			return;
		}

		/* setup parameters to the IOCTL call */
		memset(&param, 0, sizeof(struct i2c_smbus_ioctl_data));
		memset(&smbus_data, 0, sizeof(union i2c_smbus_data));
		param.data = &smbus_data;

		param.command = reg;
		param.read_write = I2C_SMBUS_WRITE;
		param.size = I2C_SMBUS_BLOCK_DATA;

		/*
		 * populate block data to be sent to the device. SMBus sets a
		 * limit of 32 bytes to be sent or received in a block.
		 */
		for (i = 1; i <= 32; i++) {
			if (fscanf(file, "0x%x ", &data) == EOF)
				break;

			param.data->block[i] = data;
			num_bytes++;
		}

		/* The very first block data should be the number of bytes
		 * in the block.
		 */
		param.data->block[0] = num_bytes;

		printf("Writing %d bytes to register 0x%.2x of device\n\n",
		       param.data->block[0], reg);

		/* Execute block write command */
		if (ioctl(fd, I2C_SMBUS, &param) == -1) {
			printf("SMBus Write Block Data command failed\n\n");
			return;
		}

		fclose(file);
	} else if (strncmp(cmdline, "license", 7) == 0) {
		show_license();
	} else if (strncmp(cmdline, "help", 4) == 0) {
		print_usage();
	} else {
		printf("\nUnknown command\n");
		print_usage();
	}
}

int main(void)
{
	char *cmdline= NULL;

	printf("SMBus sample application version: %s\n", SMBUS_APP_VERSION);
	printf("Copyright (c) 2014, Advanced Micro Devices, Inc.\n"
	       "This sample application comes with ABSOLUTELY NO WARRANTY;\n"
	       "This is free software, and you are welcome to redistribute it\n"
	       "under certain conditions; type `license` for details.\n\n");

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
