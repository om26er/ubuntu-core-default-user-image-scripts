# Create a new image

You can generate a new image with a default user via

```
 $ sudo apt install -y ubuntu-image kpartx
 $ bzr branch lp:~om26er/+junk/snapweb-kvm-runner
 $ cd snapweb-kvm-runner
 $ sudo ./create-image.sh
```

To create image for DragonBoard run

```
 $ sudo ./create-image.sh dragonboard
```

Other supported boards are pi2 and pi3


# Generate user password

You can generate the password for the system user assertion via

```
 $ python3 -c 'import crypt; print(crypt.crypt("test", crypt.mksalt(crypt.METHOD_SHA512)))'
```
