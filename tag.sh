tags=( "v1.17.6-rc1" "v1.17.6-rc2" "v1.17.6-rc3" "v1.17.6-rc4" "v1.18.0-rc1" "v1.18.0-rc2" "v1.18.0-rc3" "v1.18.0-rc4" "v2.0.1-rc1" ) 

for i in ${!tags[@]};
do
  tag=${tags[$i]}
  git tag -d ${tag}
  git push --delete origin ${tag}
done
