// SPDX-License-Identifier: GPL-2.0
/*
 *  linux/drivers/char/relaxed_devmem/relaxed_devmem.c
 *
 *  Relaxed /dev/devmem for PCIe MMIO access
 *
 *  This driver provides a relaxed version of /dev/mem that allows
 *  access to PCIe MMIO space even when CONFIG_STRICT_DEVMEM is enabled.
 *
 *  Based on drivers/char/mem.c
 */

#include <linux/mm.h>
#include <linux/miscdevice.h>
#include <linux/slab.h>
#include <linux/vmalloc.h>
#include <linux/mman.h>
#include <linux/random.h>
#include <linux/init.h>
#include <linux/tty.h>
#include <linux/capability.h>
#include <linux/ptrace.h>
#include <linux/device.h>
#include <linux/highmem.h>
#include <linux/backing-dev.h>
#include <linux/shmem_fs.h>
#include <linux/splice.h>
#include <linux/pfn.h>
#include <linux/export.h>
#include <linux/io.h>
#include <linux/uio.h>
#include <linux/uaccess.h>
#include <linux/security.h>
#include <linux/sysfs.h>
#include <asm/sysreg.h>

static inline unsigned long size_inside_page(unsigned long start,
					     unsigned long size)
{
	unsigned long sz;

	sz = PAGE_SIZE - (start & (PAGE_SIZE - 1));

	return min(sz, size);
}

static inline bool should_stop_iteration(void)
{
	if (need_resched())
		cond_resched();
	return signal_pending(current);
}

static ssize_t read_relaxed_devmem(struct file *file, char __user *buf,
				   size_t count, loff_t *ppos)
{
	phys_addr_t p = *ppos;
	ssize_t read, sz;
	void *ptr;
	char *bounce;

	if (p != *ppos)
		return 0;

	read = 0;

	bounce = kmalloc(PAGE_SIZE, GFP_KERNEL);
	if (!bounce)
		return -ENOMEM;

	while (count > 0) {
		unsigned long remaining;

		sz = size_inside_page(p, count);

		ptr = xlate_dev_mem_ptr(p);
		if (!ptr)
			goto failed;

		memcpy(bounce, ptr, sz);
		unxlate_dev_mem_ptr(p, ptr);

		remaining = copy_to_user(buf, bounce, sz);
		if (remaining)
			goto failed;

		buf += sz;
		p += sz;
		count -= sz;
		read += sz;
		if (should_stop_iteration())
			break;
	}
	kfree(bounce);

	*ppos += read;
	return read;

failed:
	kfree(bounce);
	return -EFAULT;
}

static ssize_t write_relaxed_devmem(struct file *file, const char __user *buf,
				    size_t count, loff_t *ppos)
{
	phys_addr_t p = *ppos;
	ssize_t written, sz;
	unsigned long copied;
	void *ptr;

	if (p != *ppos)
		return -EFBIG;

	written = 0;
	while (count > 0) {
		sz = size_inside_page(p, count);

		ptr = xlate_dev_mem_ptr(p);
		if (!ptr) {
			if (written)
				break;
			return -EFAULT;
		}

		copied = copy_from_user(ptr, buf, sz);
		unxlate_dev_mem_ptr(p, ptr);
		if (copied) {
			written += sz - copied;
			if (written)
				break;
			return -EFAULT;
		}

		buf += sz;
		p += sz;
		count -= sz;
		written += sz;
		if (should_stop_iteration())
			break;
	}

	*ppos += written;
	return written;
}

static int mmap_relaxed_devmem(struct file *file, struct vm_area_struct *vma)
{
	size_t size = vma->vm_end - vma->vm_start;

	vma->vm_page_prot = pgprot_noncached(vma->vm_page_prot);

	if (remap_pfn_range(vma, vma->vm_start, vma->vm_pgoff,
			     size, vma->vm_page_prot)) {
		return -EAGAIN;
	}
	return 0;
}

static long relaxed_devmem_ioctl(struct file *file, unsigned int cmd,
				 unsigned long arg)
{
	return -ENOTTY;
}

static int relaxed_devmem_open(struct inode *inode, struct file *filp)
{
	return capable(CAP_SYS_RAWIO) ? 0 : -EPERM;
}

static ssize_t lsuctlr2_el_show(struct device *dev,
				 struct device_attribute *attr, char *buf)
{
	u64 val;
	asm volatile("mrs %0, s3_1_c15_c6_2" : "=r"(val));
	return sprintf(buf, "0x%016llx\n", val);
}

static ssize_t lsuctlr2_el_store(struct device *dev,
				  struct device_attribute *attr,
				  const char *buf, size_t count)
{
	u64 val;
	int ret;

	ret = kstrtou64(buf, 0, &val);
	if (ret)
		return ret;

	asm volatile("msr s3_1_c15_c6_2, %0" :: "r"(val));
	return count;
}

static DEVICE_ATTR_RW(lsuctlr2_el);

static struct attribute *relaxed_devmem_attrs[] = {
	&dev_attr_lsuctlr2_el.attr,
	NULL,
};

static struct attribute_group relaxed_devmem_attr_group = {
	.attrs = relaxed_devmem_attrs,
};

static const struct file_operations relaxed_devmem_fops = {
	.llseek		= generic_file_llseek,
	.read		= read_relaxed_devmem,
	.write		= write_relaxed_devmem,
	.mmap		= mmap_relaxed_devmem,
	.unlocked_ioctl	= relaxed_devmem_ioctl,
	.compat_ioctl	= relaxed_devmem_ioctl,
	.open		= relaxed_devmem_open,
};

static struct miscdevice relaxed_devmem_dev = {
	MISC_DYNAMIC_MINOR,
	"relaxed_devmem",
	&relaxed_devmem_fops
};

static int __init relaxed_devmem_init(void)
{
	int ret;

	ret = misc_register(&relaxed_devmem_dev);
	if (ret)
		return ret;

	ret = sysfs_create_group(&relaxed_devmem_dev.this_device->kobj,
				  &relaxed_devmem_attr_group);
	if (ret) {
		misc_deregister(&relaxed_devmem_dev);
		return ret;
	}

	pr_info("relaxed_devmem: /dev/relaxed_devmem registered\n");
	return 0;
}

static void __exit relaxed_devmem_exit(void)
{
	sysfs_remove_group(&relaxed_devmem_dev.this_device->kobj,
			   &relaxed_devmem_attr_group);
	misc_deregister(&relaxed_devmem_dev);
}

module_init(relaxed_devmem_init);
module_exit(relaxed_devmem_exit);

MODULE_LICENSE("GPL");
MODULE_AUTHOR("PCIe BAR Benchmark");
MODULE_DESCRIPTION("Relaxed /dev/mem for PCIe MMIO access");
