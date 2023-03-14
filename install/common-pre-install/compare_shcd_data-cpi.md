# Compare the SHCD Data with CVT Inventory Data


## 1. Generate paddle file using the canu validate tool

1. Generate the paddle file.

   Example script:

   ```
   canu validate shcd --shcd CrayInc-ShastaRiver-Groot-RevE12.xlsx --architecture V1 --tabs 40G_10G,NMN,HMN --corners I12,Q38,I13,Q21,J20,U38 --json --out cabling.json
   ```

   After running this, `cabling.json` file will be created in the same directory from where the previous command was run.

## 2.  Store SHCD Data in CVT Database

1. Insert the SHCD data into the CVT database using the paddle file generated in the [Step 1](#generate-paddle-file-using-the-canu-validate-tool) using one of the following options.

   Option 1: Run the following script: `./parse_shcd.py --canu_json_file cabling.json`

   Option 2: Run the following command: `cm cvt parse shcd --canu_json_file cabling.json`

   Post successful run, a snapshot ID along with the timestamp will be created and the data will be inserted into the table named SHCD_DATA. 
 
## 3. Collect CVT inventory data

1. Collect the CVT inventry data by using one of the following options.

   Option 1: Run the following script: `./run_inv_hpcm.py`

   Option 2: Run the following command: `cm cvt discover` (provide all the credentials mentioned in the help menu)

   The script inserts data into the respective inventory tables and snapshot IDs will be created along with the timestamps.
 
## 4. Compare the SHCD snapshot and CVT snapshot

1. Display the list of generated snapshot IDs using one of the following options.

   Option 1: Run the following script: `./shcd_compare.py --list`

   Option 2: Run the following command: `cm cvt shcd compare --list`
 
2. Compare the CVT and SHCD snapshots using one of the following options.

   Option 1: Run the following script: 
   
   ```
   ./shcd_compare.py --shcd_id c4b166df-7678-4484-8762-87104de8d117 --cvt_id 84e208e3-7b0d-4ce5-9a03-95bee60714d8
   ```

   Option 2: Run the following command: 
   
   ```
   cm cvt shcd compare --shcd_id c4b166df-7678-4484-8762-87104de8d117 --cvt_id 84e208e3-7b0d-4ce5-9a03-95bee60714d8
   ```

   In the previous command, `--shcd_id` accepts the snapshot ID created while inserting into SHCD_DATA table and `--cvt_id` accepts the snapshot ID created while inserting into Management Inventory tables.
 
   In the previous output, wherever there is a difference in the data found, the left hand side is the data from SHCD and the right hand side is the data from CVT (SHCD => CVT). Under the Result column `Found in CVT Data` implies the data is present only in the CVT inventory and not found in the SHCD data, `Not Found in CVT Data` implies the data is present only in the SHCD data and not found in the CVT inventory. And the Difference Found is resulted along with the display of the mismatch found between both the data.


