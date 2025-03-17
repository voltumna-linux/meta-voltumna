#ifndef _GPIO_TEST_H_
#define _GPIO_TEST_H_



/* IOCTL numbers */

typedef struct {
	int offset;
	int value;
}debug_data;

#define GPIO_TEST_IOC_MAGIC			'k'
#define GPIO_IOC_SWCTRLIN  _IOW(GPIO_TEST_IOC_MAGIC, 1, debug_data)
#define GPIO_IOC_SWCTRLEN  _IOW(GPIO_TEST_IOC_MAGIC, 2, debug_data)

#endif /* _GPIO_TEST_H_ */
