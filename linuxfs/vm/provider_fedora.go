// SPDX-License-Identifier: GPL-3.0-or-later

package vm

import "fmt"

const fedoraVersion = "42"

// FedoraProvider uses Fedora Cloud Generic images.
// Useful when SELinux or RPM-based tooling is required.
type FedoraProvider struct{}

func (FedoraProvider) Name() string { return "fedora" }

func (FedoraProvider) ImageURL(arch Arch) string {
	// Fedora 42+ filename format: Fedora-Cloud-Base-Generic-<ver>-1.1.<arch>.qcow2
	// https://fedoraproject.org/cloud/download
	return fmt.Sprintf(
		"https://download.fedoraproject.org/pub/fedora/linux/releases/%s/Cloud/%s/images/Fedora-Cloud-Base-Generic-%s-1.1.%s.qcow2",
		fedoraVersion, arch.FedoraString(), fedoraVersion, arch.FedoraString(),
	)
}

func (FedoraProvider) ImageSHA256(_ Arch) string { return "" }
func (FedoraProvider) ImageFormat() string        { return "qcow2" }

func (FedoraProvider) CloudInitPackages() []string {
	return []string{
		"btrfs-progs",
		"e2fsprogs",
		"xfsprogs",
		"dosfstools",
		"ntfs-3g",
		"lvm2",
		"cryptsetup",
		"fuse3",
		"rsync",
		// ZFS on Fedora requires the ZFS on Linux COPR repo; it is not in
		// the default Fedora repos. Install zfs-fuse as a lightweight
		// alternative that is available without extra repos.
		"zfs-fuse",
	}
}

func (FedoraProvider) CloudInitRuncmds() []string {
	return []string{
		"systemctl enable sshd",
		"systemctl start sshd",
		// Sentinel written last so waitForCloudInit knows runcmd completed.
		"touch /run/cloud-init-custom-done",
	}
}

func (FedoraProvider) DefaultUser() string  { return "fedora" }
func (FedoraProvider) DefaultShell() string { return "/bin/bash" }
