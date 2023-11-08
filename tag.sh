tags=( "v1.17.5-rc1" "v1.17.5-rc2" "v1.17.5-rc3" "v1.17.5-rc4" "v1.17.5-rc5" ) 

for i in ${!tags[@]};
do
  tag=${tags[$i]}
  git tag -d ${tag}
  git push --delete origin ${tag}
done