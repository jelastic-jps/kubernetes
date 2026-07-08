#!/bin/bash
# set -x

# components
K9S="0.51.0"
K9S_SHA256="c3752ad51a5a4015a113819c4eeb6e55a4d0e4b8e652494797532f6fc8161dd7"
STERN="1.34.0"
STERN_SHA256="7754adfa653939240f7d20fff4ada9b69cda40c9e70732301f67bb8045f1ef3e"
KUBECTX="0.9.5"
KUBECTX_SHA256="a2247ffd23e79f89abdd0e8173379d7172511f02a3f63c9936d3824e0dd60648"
KUBENS_SHA256="acc1a9c7f6b722fbe5fad25dd0e784a7335d18436b9c414ab996629e82702cba"
KUBECTX_COMPLETION_SHA256="3a3ada36a5ada06eb0d2d102d85e7878f22029ef5d7f11db7fc7e163ee02ce83"
KUBENS_COMPLETION_SHA256="f075a473f87bffd17a8187d187423c2f44ada0b978c333e378890feefe172e9d"

download_and_install_binary() {
	local name="${1}"
	local url="${2}"
	local sha256="${3}"
	local binary="${4}"
	local tmp_dir
	local archive

	tmp_dir="$(mktemp -d)" || return 1
	archive="${tmp_dir}/${name}.tar.gz"
	wget -nv -O "${archive}" "${url}" || { rm -rf "${tmp_dir}"; return 1; }
	echo "${sha256}  ${archive}" | sha256sum -c - || { rm -rf "${tmp_dir}"; return 1; }
	tar xzf "${archive}" -C "${tmp_dir}" "${binary}" || { rm -rf "${tmp_dir}"; return 1; }
	install -m 0755 "${tmp_dir}/${binary}" "/usr/bin/${binary}" || { rm -rf "${tmp_dir}"; return 1; }
	rm -rf "${tmp_dir}"
}

download_and_install_file() {
	local name="${1}"
	local url="${2}"
	local sha256="${3}"
	local destination="${4}"
	local tmp_file

	tmp_file="$(mktemp)" || return 1
	wget -nv -O "${tmp_file}" "${url}" || { rm -f "${tmp_file}"; return 1; }
	echo "${sha256}  ${tmp_file}" | sha256sum -c - || { rm -f "${tmp_file}"; return 1; }
	install -m 0644 "${tmp_file}" "${destination}" || { rm -f "${tmp_file}"; return 1; }
	rm -f "${tmp_file}"
}

( ( echo "$(date): --- cplane postconfig started";

	# utilities
	echo "$(date): retrieving k8s utilities";
	[ -n "${K9S}" ] && {
		download_and_install_binary "k9s" "https://github.com/derailed/k9s/releases/download/v${K9S}/k9s_Linux_amd64.tar.gz" "${K9S_SHA256}" "k9s" || exit 1;
	};
	[ -n "${STERN}" ] && {
		download_and_install_binary "stern" "https://github.com/stern/stern/releases/download/v${STERN}/stern_${STERN}_linux_amd64.tar.gz" "${STERN_SHA256}" "stern" || exit 1;
		/usr/bin/stern --completion=bash > /etc/bash_completion.d/stern.bash;
	};
	[ -n "${KUBECTX}" ] && {
		download_and_install_binary "kubectx" "https://github.com/ahmetb/kubectx/releases/download/v${KUBECTX}/kubectx_v${KUBECTX}_linux_x86_64.tar.gz" "${KUBECTX_SHA256}" "kubectx" || exit 1;
		download_and_install_binary "kubens" "https://github.com/ahmetb/kubectx/releases/download/v${KUBECTX}/kubens_v${KUBECTX}_linux_x86_64.tar.gz" "${KUBENS_SHA256}" "kubens" || exit 1;
		download_and_install_file "kubectx-completion" "https://raw.githubusercontent.com/ahmetb/kubectx/v${KUBECTX}/completion/kubectx.bash" "${KUBECTX_COMPLETION_SHA256}" "/etc/bash_completion.d/kubectx.bash" || exit 1;
		download_and_install_file "kubens-completion" "https://raw.githubusercontent.com/ahmetb/kubectx/v${KUBECTX}/completion/kubens.bash" "${KUBENS_COMPLETION_SHA256}" "/etc/bash_completion.d/kubens.bash" || exit 1;
	};

	# validate cplane configuration
	/usr/local/sbin/k8sm-config -f

	# cleanup
	rm -f /tmp/jelastic-{init,conf}-mark;

	echo "$(date): --- cplane postconfig finished";
) &>>/var/log/kubernetes/k8s-cplane-postconfig.log & )&

echo "${HOSTNAME} cplane postconfig spawned"

exit 0
