function docker-volume-sandbox --description "Run a container with a volume seeded from a local directory, sync back on exit"
    argparse 'h/help' 'd/dir=' 'i/image=' 'm/mount=' 'e/env=+' -- $argv
    or return 1

    if set -q _flag_help
        echo "Usage: docker-volume-sandbox -d <host-dir> -i <image> [-m <mount-point>] [-e VAR=val]..."
        echo ""
        echo "Options:"
        echo "  -d, --dir     Host directory to seed volume from (required)"
        echo "  -i, --image   Docker image to run (required)"
        echo "  -m, --mount   Mount point inside container (default: /input)"
        echo "  -e, --env     Environment variable to pass (can be repeated)"
        return 0
    end

    if not set -q _flag_dir; or not set -q _flag_image
        echo "Error: --dir and --image are required"
        return 1
    end

    set -l host_dir (realpath $_flag_dir)
    set -l image $_flag_image
    set -l mount_point (set -q _flag_mount; and echo $_flag_mount; or echo "/input")
    set -l volume_name "sandbox-"(random)

    # Build env var args
    set -l env_args
    if set -q _flag_env
        for e in $_flag_env
            set -a env_args -e $e
        end
    end

    echo "Creating volume $volume_name..."
    docker volume create $volume_name
    or return 1

    echo "Seeding volume from $host_dir..."
    docker run --rm \
        -v $volume_name:/data \
        -v $host_dir:/source:ro \
        alpine cp -a /source/. /data/
    or begin
        docker volume rm $volume_name
        return 1
    end

    echo "Running $image with volume mounted at $mount_point..."
    docker run -it --rm \
        $env_args \
        -v $volume_name:$mount_point \
        $image $argv

    echo "Copying volume contents back to $host_dir..."
    docker run --rm \
        -v $volume_name:/data:ro \
        -v $host_dir:/dest \
        alpine cp -a /data/. /dest/

    echo "Cleaning up volume..."
    docker volume rm $volume_name
end
