function create_disk_image() {
    log_info "Creating Mender compatible disk-image"

    img_path=deploy/${image_name}-mender.img

    log_info "Total disk size: $(disk_sectors_to_mb ${disk_image_total_sectors}) MiB"
    log_info "  Boot partition    $(disk_sectors_to_mb ${boot_part_sectors}) MiB"
    log_info "  RootFS partitions $(disk_sectors_to_mb ${rootfs_part_sectors}) MiB x 2"
    log_info "  Data partition    $(disk_sectors_to_mb ${data_part_sectors}) MiB"

    # Initialize sdcard image file
    run_and_log_cmd \
      "dd if=/dev/zero of=${img_path} bs=512 count=0 seek=${disk_image_total_sectors} status=none"

    # boot_part_start, is defined at the beginning of this file
    boot_part_end=$(( ${boot_part_start} + ${boot_part_sectors} - 1 ))

    rootfsa_start=$(disk_align_sectors ${boot_part_end} ${MENDER_PARTITION_ALIGNMENT} )
    rootfsa_end=$(( ${rootfsa_start} + ${rootfs_part_sectors} - 1 ))

    rootfsb_start=$(disk_align_sectors ${rootfsa_end} ${MENDER_PARTITION_ALIGNMENT} )
    rootfsb_end=$(( ${rootfsb_start} + ${rootfs_part_sectors} - 1 ))

    data_start=$(disk_align_sectors ${rootfsb_end} ${MENDER_PARTITION_ALIGNMENT} )
    data_end=$(( ${data_start} + ${data_part_sectors} - 1 ))

    # Create partition table. TODO: GPT support
    run_and_log_cmd "${PARTED} -s ${img_path} mklabel msdos"
    run_and_log_cmd "${PARTED} -s ${img_path} unit s mkpart primary fat32 ${boot_part_start} ${boot_part_end}"
    run_and_log_cmd "${PARTED} -s ${img_path} set 1 boot on"
    run_and_log_cmd "${PARTED} -s ${img_path} -- unit s mkpart primary ext2 ${rootfsa_start} ${rootfsa_end}"
    run_and_log_cmd "${PARTED} -s ${img_path} -- unit s mkpart primary ext2 ${rootfsb_start} ${rootfsb_end}"
    run_and_log_cmd "${PARTED} -s ${img_path} -- unit s mkpart primary ext2 ${data_start} ${data_end}"
    run_and_log_cmd "${PARTED} -s ${img_path} print"

    # Write boot-gap
    if [ "${MENDER_COPY_BOOT_GAP}" == "y" ]; then
      log_info "Writing boot gap of size: ${boot_part_sectors} (sectors)"
      disk_write_at_offset "${output_dir}/boot-gap.bin" "${img_path}" "1"
    fi

    # Burn Partitions
    disk_write_at_offset "${boot_part}" "${img_path}" "${boot_part_start}"
    disk_write_at_offset "${output_dir}/rootfs.img" "${img_path}" "${rootfsa_start}"
    disk_write_at_offset "${output_dir}/rootfs.img" "${img_path}" "${rootfsb_start}"
    disk_write_at_offset "${output_dir}/data.img" "${img_path}" "${data_start}"

    log_info "Performing platform specific package operations (if any)"
    platform_package

    # Create bmap index
    if [ "${MENDER_USE_BMAP}" == "y" ]; then
      BMAP_TOOL="/usr/bin/bmaptool"
      if [ ! -e "${BMAP_TOOL}" ]; then
        log_error "You have enabled the MENDER_USE_BMAP option, but we could not find the required 'bmaptool'"
        log_fatal "You can install 'bmaptool' with: apt-get install bmap-tools (on Debian based distributions)"
      fi
      run_and_log_cmd "${BMAP_TOOL} create ${img_path} > ${img_path}.bmap"
    fi

    case "${MENDER_COMPRESS_DISK_IMAGE}" in
      gzip)
        log_info "Compressing ${img_path}.gz"
        run_and_log_cmd "pigz --best --force ${img_path}"
        ;;
      lzma)
        log_info "Compressing ${img_path}.xz"
        run_and_log_cmd "pxz --best --force ${img_path}"
        ;;
      none)
        :
        ;;
      *)
        log_fatal "Unknown MENDER_COMPRESS_DISK_IMAGE value: ${MENDER_COMPRESS_DISK_IMAGE}"
        ;;
    esac
}

