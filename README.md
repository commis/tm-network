# 代码下载与编译

mkdir -p $GOPATH/src/github.com/ethereum

cd $GOPATH/src/github.com/ethereum

git clone http://192.168.1.232/ethereum/go-ethereum.git

mkdir -p $GOPATH/src/github.com/tendermint

git clone http://192.168.1.232/tendermint/tendermint.git

git clone http://192.168.1.232/tendermint/ethermint.git

mkdir -p $GOPATH/src/energy.com

cd $GOPATH/src/energy.com/

git clone http://192.168.1.232/blockchain/install-ethermint.git

cd $GOPATH/src/energy.com/install-ethermint

make build

`说明:`

    编译所需要的依赖包库:
        http://192.168.1.232/blockchain/go-dependencies.git

# 运行脚本启动网络

cd $GOPATH/src/energy.com/install-ethermint

make [up|down|add|start|del]

`说明:`

    参数介绍:
        up：   启动初始化网络节点，包含一个监控节点ethermint/monitor:x86_64-1.2.0
        down： 删除网络节点，所有节点容器都会被删除掉
        add：  新增网络节点，支持一次添加多个normal节点，支持恢复一个损坏的共识节点
        start：启动新增加的网络节点（或者恢复的共识节点）
        del：  新增的普通节点可以直接删除掉，如果是恢复的共识节点，执行还命令后也会被删除，请注意
    
    网络节点配置文件，可以根据需要修改：
        $GOPATH/src/energy.com/install-ethermint/script/.env
        
        文件配置解释：
            SYS_ubuntu=ubuntu:16.04 //监控节点镜像的操作系统
            localhost=192.168.56.4 //本地IP地址，脚本判断是否本机使用
            DataDir=/home/share/chaindata //节点数据目录路径
            
            # 网络初始启动节点，type为类型：1为共识节点，0为普通节点
            init:peer1=192.168.56.4,type=1
            init:peer2=192.168.56.4,type=1
            init:peer3=192.168.56.4,type=1
            init:peer4=192.168.56.4,type=1
            init:peer5=192.168.56.4,type=0
            
            # 动态新增普通节点或者恢复共识节点
            # add:from_node 指定要恢复的共识节点
            # add:from_data 指定从那个节点恢复数据
            # add:peer*     指定新增的节点，如果配置了from_node说明是恢复节点，一次只能恢复一个共识节点
            
            # add:from_node=peer1 //如果不是恢复共识节点，可以注释掉改行
            add:from_data=peer5
            add:peer6=192.168.56.4
            add:peer7=192.168.56.4
            
    监控节点说明：
    	监控节点为开发测试使用。根据本机需要修改监控节点的IP地址，配置文件为jar包的application.yml文件。
    	
    	如果不需要启动监控节点，可以修改Makefile文件：
    	up:
    	    @cd script && ./network_setup.sh -t up
    	    @cd monitor && make up #如果不需要监控，请注释掉该行
    	down:
    	    @cd script && ./network_setup.sh -t down
    	    @cd monitor && make down #如果不需要监控，请注释掉该行
    	    


