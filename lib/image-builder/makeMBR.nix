{ stdenvNoCC, lib, utillinux, size }:

/*  */ let scope = { "diskImage.makeMBR" =

let
  inherit (lib) concatMapStringsSep optionalString;

  # List of known mappings of MBR partition types to filesystems.
  types = {
    "FAT32" =  "b";
    "ESP"   = "ef";
    "ext2"  = "83";
    "ext3"  = "83";
    "ext4"  = "83";
  };
in
{
  name
  , partitions
}:

let
  _name = name;

  eachPart = partitions: fn: (
    concatMapStringsSep "\n" (partition:
      fn partition
  ) partitions);
in
stdenvNoCC.mkDerivation rec {
  name = "disk-image-${_name}";
  filename = "${_name}.img";
  img = "${placeholder "out"}/${filename}";

  buildInputs = [ utillinux ];

  buildCommand = ''
    mkdir -p $out

    cat <<EOF > script.sfdisk
    label: dos
    EOF

    # `sfdisk` starts at 1MiB by default, let's use the same default.
    totalSize=${toString (size.MiB 1)}

    echo
    echo "Gathering information about partitions."
    ${eachPart partitions (partition: ''
      input_img="${partition}/${partition.filename}"
      start=$totalSize
      size=$(($(du -B 512 --apparent-size "$input_img" | awk '{ print $1 }') * 512))
      totalSize=$(( totalSize + size ))
      echo " -> ${partition.name}: $size / ${partition.filesystemType}"

      (
      # The size is /1024; otherwise it's in sectors.
      echo -n 'start='"$((start/1024))"'KiB'
      echo -n ', size='"$((size/1024))"'KiB'
      echo -n ', type=${types."${partition.filesystemType}"}'
      ${optionalString (partition ? bootable && partition.bootable)
          "echo -n ', bootable'"}
      echo "" # Finishes the command
      ) >> script.sfdisk
    '')}

    echo
    echo "Making image, $totalSize bytes..."
    truncate -s $totalSize $img
    sfdisk $img < script.sfdisk

    totalSize=${toString (size.MiB 1)}
    echo
    echo "Writing partitions into image"
    ${eachPart partitions (partition: ''
      input_img="${partition}/${partition.filename}"
      start=$totalSize
      size=$(($(du -B 512 --apparent-size "$input_img" | awk '{ print $1 }') * 512))
      totalSize=$(( totalSize + size ))
      echo " -> ${partition.name}: $size / ${partition.filesystemType}"

      set -x
      echo "$start / $size"
      dd conv=notrunc if=$input_img of=$img seek=$((start/512)) count=$((size/512)) bs=512
      set +x
    '')}

    ls -lh $img
  '';
}

/*  */ ;}; in scope."diskImage.makeMBR"
