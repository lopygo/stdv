#!/bin/bash
# 不要使用 sh ./xxx.sh 来运行本脚本，应该直接 ./xxx.sh 或 bash ./xxx.sh

versionDataFile="version.dat"

data_dir="./.version"

# 取得脚本所在位置，不是工作目录cwd，是脚本所在位置
script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# echo "脚本所在的目录路径：$script_dir"

# 定义有效的参数数组
valid_args=("init" "add" "do")

# 检查第一个参数是否在有效的参数数组中
if [[ ! " ${valid_args[@]} " =~ " $1 " ]]; then
    echo -n "第一个参数无效！只能使用 "
    for element in "${valid_args[@]}"; do
        echo -n "${element}, "
    done
    echo 
    exit 1
fi


# 
#  lib func
# 

check_version(){
    local version=$1

    if [[ ! "$version" =~ ^v[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
        echo "版本号格式 v0.0.0"
        exit 1
    fi
}

dt_filename(){
    # echo ${script_dir}/$versionDataFile
    echo ${data_dir}/${versionDataFile}

}

read_version() {
    local filename=$(dt_filename)

    # 检查文件是否存在
    if [ ! -f "$filename" ]; then
        echo "文件 '$filename' 不存在。请先执行'init'"
        exit 1
    fi

    # 读取文件内容
    local file_content=$(<"$filename")

    # 提取文件中的前两行
    local version=$(echo "$file_content" | sed -n '1p')
    local rnd=$(echo "$file_content" | sed -n '2p')
    local signed=$(echo "$file_content" | sed -n '3p')

    local sign=`version_sign $version $rnd`

    # 验证签名
    if [ "$sign" != "$signed" ]; then
        echo "文件签名错误。请先执行'init'"
        exit 1
    fi

    echo $version
}


write_version(){
    local version=$1

    local random_number=$RANDOM

    local sign=$(version_sign $version $random_number)
    
    local dtFile=`dt_filename`
    echo $version > $dtFile
    echo $random_number >> $dtFile
    echo $sign >> $dtFile
}

# arg0 version 
# arg1 rand number
version_sign(){
    md5_hash=$(echo -n "${1}-----${2}" | md5sum)
    md5_hash=${md5_hash%% *}  # 删除输出中的破折号和文件名部分
    echo $md5_hash
}

# 版本号递增函数
increment_version() {
    local version=$1
    local position=$2
    local delimiter="."

    # 检查第一个参数是否符合版本号格式 v0.0.0
    if [[ ! "$version" =~ ^v[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
        echo "版本号格式 v0.0.0"
        exit 1
    fi

    # 检查第二个参数是否为数字
    if [[ ! "$position" =~ ^[0-9]+$ ]]; then
        position=0
    fi

    if ((position > 2)); then
        position=0
    fi

    local versionS=${version:1}
    # 将版本号拆分为数组
    IFS=$delimiter read -ra parts <<< "$versionS"

    local index=$((-1 - position))


    local last_part=${parts[$index]}
    local new_last_part=$((last_part + 1))
    if ((index < -1)); then
        parts[-1]=0
    fi

    if ((index < -2)); then
        parts[-2]=0

    fi

    parts[$index]=$new_last_part

    # 拼接新版本号
    local new_version=$(IFS=$delimiter ; echo "${parts[*]}")

    echo "v$new_version"
}


# ctrl


ctrl_init(){
    local version=$1
    local force=$2

    check_version "$version"

    if [ $? -ne 0 ]; then
        echo "version invalid: "$current
        exit 1
    fi

    mkdir -p $data_dir

    # file if exists
    local filename=$(dt_filename)

    # 检查文件是否存在
    if [ -f "$filename" ]; then

        if [ "$force" != "-f" ]; then
            echo "文件 '$filename' 已经存在。请使用 '-f'来覆盖。'$0 init $version -f'"
            exit 1
        fi 
    fi

    write_version "$version"

     if [ $? -ne 0 ]; then
        echo "init version error: "$current
        exit 1
    fi

    echo "$version"
}


ctrl_add(){
    local tp=$1

    current=`read_version`
    if [ $? -ne 0 ]; then
        echo "脚本出现异常或产生了标准错误1" $current
        exit 1
    fi

    # increment_version "$current" 
    newV=`increment_version "$current" "$tp"`
    if [ $? -ne 0 ]; then
        echo "脚本出现异常或产生了标准错误2: " $newV
        exit 1
    fi

    writeRes=`write_version "$newV"`
    if [ $? -ne 0 ]; then
        echo "脚本出现异常或产生了标准错误3" $writeRes
        exit 1
    fi
    echo $newV
}

ctrl_do(){
    local tp=$1

    local version=`ctrl_add $tp`
    if [ $? -ne 0 ]; then
        echo "add version error: " $version
        exit 1
    fi

    echo "new version: "$version

    local gitRes=`git tag -a "$version" -m "release"`
    if [ $? -ne 0 ]; then
        echo "add version error: " $gitRes
        exit 1
    fi
    echo "git add tag($version) ok"

    # change log
    local chlog=`conventional-changelog -p angular -i CHANGELOG.md -s -r 0`
    if [ $? -ne 0 ]; then
        echo "gen changelog error: " $chlog
        exit 1
    fi
    echo "gen changelog ok"

    local tagLog=`git tag -d "$version"`
    if [ $? -ne 0 ]; then
        echo "delete tag error: " $tagLog
        exit 1
    fi
    echo "delete tag(${version}) before add changelog"

    local cmt=`git commit CHANGELOG.md -m "commit CHANGELOG.md before add tag"`
    if [ $? -ne 0 ]; then
        echo "re commit changelog error: " $cmt
        exit 1
    fi
    echo "gen changelog success"

    gitRes=`git tag -a "$version" -m "release"`
    if [ $? -ne 0 ]; then
        echo "add version error: " $gitRes
        exit 1
    fi
    echo "git re add tag($version) ok "

    echo "done. do 'git push --tags or'"
}

# 
res=""
if [ "$1" == "init" ] ; then
    res=`ctrl_init "$2" "$3"`
elif [ "$1" == "add" ]; then
    res=`ctrl_add $2`
elif [ "$1" == "do" ]; then
    res=$(ctrl_do $2)
else 
    echo "no this command"
    exit 1
fi


if [ $? -ne 0 ]; then
    echo "exec $1 error " $res
    exit 1
fi

echo -e "$res"