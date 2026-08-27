set -e

zsign -k ./.sign/pkey.p12 -p 1234 -m ./.sign/development.cer -b $1 -m ./.sign/profile.mobileprovision -o ./.sign/Euphoria.signed.ipa ./Application/Euphoria.ipa
ideviceinstaller install ./.sign/Euphoria.signed.ipa